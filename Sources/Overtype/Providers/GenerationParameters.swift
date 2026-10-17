import Foundation

/// A reasoning setting to send, in provider-neutral form. Each provider maps it
/// onto its own wire field (specs/010-model-aware-parameters,
/// contracts/request-parameters.md): `level` becomes OpenAI `reasoning_effort`,
/// Anthropic `output_config.effort`, or Gemini `thinkingLevel`; `thinkingBudget`
/// exists only for Gemini 2.5, which takes a token budget instead of a level.
public enum ReasoningSetting: Equatable {
  case level(String)
  case thinkingBudget(Int)
}

/// A request parameter the adaptive fallback may remove after the provider
/// rejects it. Only `OpenAICompatibleProvider` maps wire names onto this.
public enum DroppableParameter: String, Equatable, Hashable, CaseIterable {
  case temperature
  case reasoning
}

/// Parameters a provider rejected during this app session, so later runs skip
/// them from the first request (specs/010 FR-012). In memory only: a wrong
/// rule must not outlive the process (research R7). Keyed by provider id, base
/// URL and model, so a changed model or endpoint starts clean, and each entry
/// remembers the rejected VALUE: once the user changes it, the new value is
/// sent again instead of staying withheld until the app quits. Runs execute in
/// a `Task`, so access is serialized with a lock; the methods are synchronous,
/// which keeps the lock out of async contexts.
final class ParameterRejectionMemory: @unchecked Sendable {

  struct Key: Hashable {
    let providerID: String
    let baseURL: String
    let model: String
  }

  static let shared = ParameterRejectionMemory()

  private let lock = NSLock()
  private var rejected: [Key: [DroppableParameter: String]] = [:]

  func record(_ parameter: DroppableParameter, value: String, for key: Key) {
    lock.lock()
    defer { lock.unlock() }
    rejected[key, default: [:]][parameter] = value
  }

  /// The parameters whose remembered rejected value is exactly the value
  /// `resolved` would send now.
  func learnedRejections(
    for key: Key, matching resolved: ResolvedGenerationParameters
  ) -> Set<DroppableParameter> {
    lock.lock()
    let stored = rejected[key] ?? [:]
    lock.unlock()
    return Set(
      DroppableParameter.allCases.filter { parameter in
        guard
          let value = Self.wireValue(
            of: parameter, temperature: resolved.temperature, reasoning: resolved.reasoning)
        else { return false }
        return stored[parameter] == value
      })
  }

  /// A comparable form of the value a request carries for `parameter`.
  static func wireValue(
    of parameter: DroppableParameter, temperature: Double?, reasoning: ReasoningSetting?
  ) -> String? {
    switch parameter {
    case .temperature:
      return temperature.map { "\($0)" }
    case .reasoning:
      switch reasoning {
      case .level(let level):
        return level
      case .thinkingBudget(let budget):
        return "budget:\(budget)"
      case nil:
        return nil
      }
    }
  }
}

/// Why an action's override is not sent (shown as a warning in the editor).
public enum WithholdReason: Equatable {
  /// The model rejects this value with HTTP 400.
  case modelRejects
  /// The provider's documentation tells clients to remove it.
  case providerSaysRemove
  /// The value is not one the model supports.
  case unsupportedValue
  /// The provider kind never takes this parameter.
  case providerIgnores
  /// The provider rejected it earlier in this session (adaptive fallback).
  case learnedRejection
}

public struct WithheldOverride: Equatable {
  public let parameter: DroppableParameter
  public let reason: WithholdReason
}

/// What one request carries, plus what the editor needs to explain it.
public struct ResolvedGenerationParameters: Equatable {
  public let temperature: Double?
  public let reasoning: ReasoningSetting?
  /// What "Automatic" resolves to for this model, for the editor caption.
  public let automaticReasoning: ReasoningSetting?
  public let withheldOverrides: [WithheldOverride]
}

/// The single place that decides which optional parameters a request carries
/// (specs/010-model-aware-parameters, data-model.md "Resolution order"). Pure;
/// `ActionEngine.run` and the Actions editor both call it, so the editor's
/// caption and warnings always match the request actually sent.
enum GenerationParameterResolver {

  static func resolve(
    kind: ProviderKind, model: String, temperatureOverride: Double?, reasoningOverride: String?,
    learnedRejections: Set<DroppableParameter> = []
  ) -> ResolvedGenerationParameters {
    let profile = ModelProfiles.profile(for: kind, model: model)
    let takesReasoning = ModelProfiles.reasoningValues[kind] != nil
    var withheld: [WithheldOverride] = []

    let automatic: ReasoningSetting? = takesReasoning ? preferredSetting(of: profile) : nil

    // Reasoning: override, else the profile's preference, else nothing.
    var reasoning: ReasoningSetting?
    if let override = reasoningOverride {
      if !takesReasoning {
        withheld.append(WithheldOverride(parameter: .reasoning, reason: .providerIgnores))
      } else if let spec = profile?.reasoning, !supports(spec, override) {
        // A value the model does not support would fail the request; fall back
        // to what "Automatic" sends (FR-008).
        withheld.append(WithheldOverride(parameter: .reasoning, reason: .unsupportedValue))
        reasoning = automatic
      } else {
        reasoning = .level(override)
      }
    } else {
      reasoning = automatic
    }
    // What the editor shows for "Automatic": nothing once the provider has
    // rejected that very value this session.
    var automaticCaption = automatic
    if learnedRejections.contains(.reasoning), reasoning != nil {
      if reasoning == automatic { automaticCaption = nil }
      if reasoningOverride != nil, !withheld.contains(where: { $0.parameter == .reasoning }) {
        withheld.append(WithheldOverride(parameter: .reasoning, reason: .learnedRejection))
      }
      reasoning = nil
    }

    // Temperature: only ever the override; "Automatic" leaves it to the model.
    var temperature: Double?
    if let override = temperatureOverride {
      if let reason = temperatureWithholdReason(
        kind: kind, rule: profile?.temperature, reasoning: reasoning,
        learnedRejections: learnedRejections)
      {
        withheld.append(WithheldOverride(parameter: .temperature, reason: reason))
      } else {
        temperature = override
      }
    }

    return ResolvedGenerationParameters(
      temperature: temperature, reasoning: reasoning, automaticReasoning: automaticCaption,
      withheldOverrides: withheld)
  }

  /// `resolve`, with the session's learned rejections applied: a parameter is
  /// treated as rejected only when the value this run would send is the value
  /// the provider rejected. `ActionEngine.run` and the Actions editor both use
  /// this, so their results stay identical.
  static func resolve(
    kind: ProviderKind, model: String, temperatureOverride: Double?, reasoningOverride: String?,
    memory: ParameterRejectionMemory, key: ParameterRejectionMemory.Key
  ) -> ResolvedGenerationParameters {
    let unadjusted = resolve(
      kind: kind, model: model, temperatureOverride: temperatureOverride,
      reasoningOverride: reasoningOverride)
    let learned = memory.learnedRejections(for: key, matching: unadjusted)
    guard !learned.isEmpty else { return unadjusted }
    return resolve(
      kind: kind, model: model, temperatureOverride: temperatureOverride,
      reasoningOverride: reasoningOverride, learnedRejections: learned)
  }

  private static func preferredSetting(of profile: ModelProfile?) -> ReasoningSetting? {
    switch profile?.reasoning {
    case .levels(_, let preferred):
      return .level(preferred)
    case .thinkingBudget(_, let preferred):
      return .thinkingBudget(preferred)
    case nil:
      return nil
    }
  }

  /// Overrides are text, so a budget-based model supports none of them.
  private static func supports(_ spec: ReasoningSpec, _ value: String) -> Bool {
    switch spec {
    case .levels(let supported, _):
      return supported.contains(value)
    case .thinkingBudget:
      return false
    }
  }

  private static func temperatureWithholdReason(
    kind: ProviderKind, rule: TemperatureRule?, reasoning: ReasoningSetting?,
    learnedRejections: Set<DroppableParameter>
  ) -> WithholdReason? {
    if ModelProfiles.kindsWithoutTemperature.contains(kind) { return .providerIgnores }
    switch rule {
    case .rejected:
      return .modelRejects
    case .discouraged:
      return .providerSaysRemove
    case .acceptedOnlyAtLevels(let levels):
      // e.g. gpt-6-luna: a temperature at any effort other than `none` is a
      // 400 (research R1).
      guard case .level(let level) = reasoning, levels.contains(level) else {
        return .modelRejects
      }
    case .accepted, nil:
      break
    }
    return learnedRejections.contains(.temperature) ? .learnedRejection : nil
  }
}
