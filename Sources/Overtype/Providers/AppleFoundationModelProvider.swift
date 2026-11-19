import Foundation
import FoundationModels

/// Apple's on-device model through the public FoundationModels framework
/// (specs/011-apple-foundation-models). Runs in process: no network request,
/// no subprocess, no API key, no endpoint.
///
/// The framework API used here exists on macOS 27 and later only, so every use
/// sits behind `#available(macOS 27, *)` and no framework type is stored in a
/// property. The linker then weak-links FoundationModels, and the app still
/// launches on macOS 13 to 26, where this provider throws
/// `.onDeviceModelUnavailable(.operatingSystemTooOld)` (research R2, R3).
public final class AppleFoundationModelProvider: AIProvider {
  /// The only model identifier this provider accepts, besides an empty one.
  /// It matches the name Apple's `fm` tool uses for the on-device model; the
  /// framework offers no way to choose a variant (research R13).
  static let systemModelID = "system"

  public let id: String
  private let timeoutSeconds: Double

  public init(config: ProviderConfig) {
    self.id = config.id
    self.timeoutSeconds = config.timeoutSeconds
  }

  /// Whether `model` names the on-device system model. Pure, unit-tested.
  static func acceptsModel(_ model: String) -> Bool {
    model.isEmpty || model == systemModelID
  }

  public func transform(_ request: TransformRequest) async throws -> String {
    guard #available(macOS 27, *) else {
      throw ProviderError.onDeviceModelUnavailable(.operatingSystemTooOld)
    }
    guard Self.acceptsModel(request.model) else {
      throw ProviderError.modelNotAvailable(model: request.model)
    }
    do {
      return try await generate(request)
    } catch {
      throw Self.providerError(from: error)
    }
  }

  @available(macOS 27, *)
  private func generate(_ request: TransformRequest) async throws -> String {
    // Permissive guardrails: Apple intends this mode for apps that transform
    // text the user supplies, which is all Overtype does. The default mode
    // refuses more ordinary text about sensitive subjects (spec Clarifications,
    // FR-013). Apple's base safety rules still apply.
    let model = SystemLanguageModel(
      useCase: .general, guardrails: .permissiveContentTransformations)

    // Checked on every run, because Apple Intelligence can be turned off or
    // the model removed while the app is running.
    if case .unavailable(let reason) = model.availability {
      throw Self.error(for: reason)
    }

    let prompt = request.userPromptTemplate.replacingOccurrences(
      of: "{{text}}", with: request.text)
    // No `maximumResponseTokens`: the diagnostic (research R7) showed that a
    // capped response comes back as truncated text with no error, which would
    // replace the whole selection with part of it. The timeout below bounds a
    // runaway answer instead. No reasoning level either: this model rejects
    // every level with `unsupportedCapability` (research R6).
    let options = GenerationOptions(temperature: request.temperature)
    let instructions = request.systemPrompt
    let seconds = timeoutSeconds

    let text = try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        // A fresh session per run, so no text from an earlier run is carried
        // into this prompt (FR-009).
        let session = LanguageModelSession(model: model, instructions: instructions)
        return try await session.respond(to: prompt, options: options).content
      }
      group.addTask {
        try await Task.sleep(nanoseconds: Self.nanoseconds(forTimeout: seconds))
        throw ProviderError.timeout
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else {
        throw ProviderError.timeout
      }
      return first
    }

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProviderError.emptyResponse
    }
    return text
  }

  /// Converts the provider timeout for `Task.sleep`. A non-finite or
  /// non-positive value from a hand-edited config would trap in `UInt64(...)`
  /// or end every run at once, so it falls back to the 30 s Settings default.
  static func nanoseconds(forTimeout seconds: Double) -> UInt64 {
    let usable = seconds.isFinite && seconds > 0 ? min(seconds, 3600) : 30
    return UInt64(usable * 1_000_000_000)
  }

  /// Maps an availability reason to a typed error (research R4).
  @available(macOS 27, *)
  static func error(for reason: SystemLanguageModel.Availability.UnavailableReason)
    -> ProviderError
  {
    switch reason {
    case .deviceNotEligible:
      return .onDeviceModelUnavailable(.deviceNotEligible)
    case .appleIntelligenceNotEnabled:
      return .onDeviceModelUnavailable(.appleIntelligenceNotEnabled)
    case .modelNotReady:
      return .onDeviceModelUnavailable(.modelNotReady)
    @unknown default:
      return .onDeviceModelUnavailable(.unknown)
    }
  }

  /// Maps any error from a run to a typed `ProviderError` (research R5).
  @available(macOS 27, *)
  static func providerError(from error: Error) -> ProviderError {
    if let providerError = error as? ProviderError {
      return providerError
    }
    if error is CancellationError {
      return .cancelled
    }
    if let modelError = error as? LanguageModelError {
      switch modelError {
      case .contextSizeExceeded(let context):
        return .contextWindowExceeded(tokenLimit: context.contextSize)
      case .rateLimited:
        return .rateLimited
      case .guardrailViolation:
        return .responseBlocked(reason: "the on-device safety guardrails")
      case .refusal:
        return .responseBlocked(reason: "the on-device model refused")
      case .unsupportedLanguageOrLocale(let context):
        return .unsupportedLanguage(code: context.languageCode.identifier)
      case .timeout:
        return .timeout
      default:
        return .onDeviceModelFailed(message: Self.description(of: modelError))
      }
    }
    if let systemError = error as? SystemLanguageModel.Error,
      case .assetsUnavailable = systemError
    {
      return .onDeviceModelUnavailable(.modelNotReady)
    }
    return .onDeviceModelFailed(message: Self.description(of: error))
  }

  /// Apple's description without a trailing period, so the message reads as
  /// one sentence inside `ProviderError.onDeviceModelFailed`.
  private static func description(of error: Error) -> String {
    let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.hasSuffix(".") ? String(text.dropLast()) : text
  }
}
