import Foundation

/// What a model accepts for `temperature` (specs/010-model-aware-parameters).
public enum TemperatureRule: Equatable {
  /// Sent when the action sets one.
  case accepted
  /// Accepted only when the effective reasoning level is one of these; any
  /// other level makes the model reject the request with HTTP 400.
  case acceptedOnlyAtLevels(Set<String>)
  /// The model rejects any non-default value with HTTP 400.
  case rejected
  /// The provider's documentation tells clients to remove it (it may degrade
  /// output or be ignored), even though the request would not fail.
  case discouraged
}

/// How a model takes its reasoning setting.
public enum ReasoningSpec: Equatable {
  /// A named level: OpenAI `reasoning_effort`, Anthropic `output_config.effort`,
  /// or Gemini `thinkingLevel`, depending on the provider kind.
  case levels(supported: [String], preferred: String)
  /// Gemini 2.5's token budget (`thinkingBudget`).
  case thinkingBudget(range: ClosedRange<Int>, preferred: Int)
}

/// Built-in knowledge about one model. Each profile is a claim taken from the
/// provider's documentation on the date in `source`; a wrong row is corrected
/// in a release, never by the user (specs/010 FR-004).
public struct ModelProfile: Equatable {
  public let kind: ProviderKind
  public let modelID: String
  public let reasoning: ReasoningSpec?
  public let temperature: TemperatureRule
  public let source: String
}

/// The built-in profile table (contracts/model-profiles.md) and the per-kind
/// data the resolver and the Settings editor need.
///
/// Per-kind data lives in dictionaries keyed by `ProviderKind`, where a
/// missing key means "none", never in an exhaustive `switch`: adding a provider
/// must stay the three-edit change constitution Principle IV requires, and a
/// new kind simply starts without profiles (research R8).
enum ModelProfiles {

  // MARK: - Per-kind data

  /// Reasoning values the Actions editor offers after "Automatic" (FR-022).
  /// A kind without an entry takes no reasoning setting at all (Ollama: its
  /// `think` option is rejected by models that lack it, feature 008).
  ///
  /// OpenAI's list keeps `minimal` although no profiled GPT-6 model supports
  /// it: earlier OpenAI reasoning models without a profile do, and for those
  /// the override is sent as written. On a profiled model the editor warns
  /// and Automatic is used instead.
  static let reasoningValues: [ProviderKind: [String]] = [
    .openAICompatible: ["none", "minimal", "low", "medium", "high", "xhigh", "max"],
    .anthropic: ["low", "medium", "high", "xhigh", "max"],
    .gemini: ["minimal", "low", "medium", "high"],
  ]

  /// Model pre-filled when the user adds a provider of this kind in Settings
  /// (FR-018). A kind without an entry starts with an empty field.
  static let suggestedDefaultModel: [ProviderKind: String] = [
    .openAICompatible: "gpt-6-luna"
  ]

  /// Kinds whose requests never carry a temperature, whatever the action sets.
  /// Anthropic: feature 007 drops it for every model, because the newest ones
  /// reject any non-default value and the latency gain comes from effort.
  static let kindsWithoutTemperature: Set<ProviderKind> = [.anthropic]

  // MARK: - Lookup

  /// The profile for `model`, matching the exact ID or a dated snapshot of it
  /// (`-YYYY-MM-DD` or `-YYYYMMDD`). Any other suffix does not match, so
  /// `gpt-6-luna` never describes a future `gpt-6-luna-mini` (research R5).
  static func profile(for kind: ProviderKind, model: String) -> ModelProfile? {
    all.first { $0.kind == kind && matches(model: model, profileID: $0.modelID) }
  }

  static func matches(model: String, profileID: String) -> Bool {
    if model == profileID { return true }
    let prefix = profileID + "-"
    guard model.hasPrefix(prefix) else { return false }
    return isDateSuffix(String(model.dropFirst(prefix.count)))
  }

  private static func isDateSuffix(_ suffix: String) -> Bool {
    let digits = suffix.replacingOccurrences(of: "-", with: "")
    let dashed = suffix.count == 10 && suffix.split(separator: "-").map(\.count) == [4, 2, 2]
    let compact = suffix.count == 8 && !suffix.contains("-")
    guard dashed || compact, digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isNumber })
    else {
      return false
    }
    guard let month = Int(digits.dropFirst(4).prefix(2)), let day = Int(digits.suffix(2)) else {
      return false
    }
    return (1...12).contains(month) && (1...31).contains(day)
  }

  // MARK: - Table

  private static let openAISource =
    "developers.openai.com: Using GPT-6 guide and gpt-6-* model pages, read 2026-10-17; "
    + "values and Luna temperature rule verified against Chat Completions 2026-10-17"
  private static let anthropicSource =
    "platform.claude.com: Effort and Thinking (sampling parameters) pages, read 2026-10-17"
  private static let geminiSource =
    "ai.google.dev: Gemini thinking, latest-model and Gemini 3.x guides, read 2026-10-17"

  static let all: [ModelProfile] = openAI + anthropic + gemini

  /// OpenAI GPT-6 family (research R1). The guide says to remove `temperature`
  /// "when reasoning effort is not `none`"; that Luna and Sol accept it AT
  /// `none` is not stated there; the quickstart Q1 diagnostic (2026-10-17)
  /// confirmed it: `gpt-6-luna` with effort `none` and temperature 0 returned
  /// HTTP 200. Astra and 6.1 Sol do not support `none`, so they never take a
  /// temperature.
  ///
  /// EVIDENCE OVER DOCUMENTATION: the model pages list `max`, but Chat
  /// Completions (the endpoint Overtype calls) rejects it for all four models;
  /// each 400 lists the supported values, which are the lists below (verified
  /// 2026-10-17, docs/compatibility.md). Do not add `max` back without a new
  /// diagnostic run.
  private static let openAI: [ModelProfile] = {
    let withNone = ["none", "low", "medium", "high", "xhigh"]
    let withoutNone = ["low", "medium", "high", "xhigh"]
    func profile(_ id: String, _ supported: [String], _ preferred: String, _ rule: TemperatureRule)
      -> ModelProfile
    {
      ModelProfile(
        kind: .openAICompatible, modelID: id,
        reasoning: .levels(supported: supported, preferred: preferred), temperature: rule,
        source: openAISource)
    }
    return [
      profile("gpt-6-luna", withNone, "none", .acceptedOnlyAtLevels(["none"])),
      profile("gpt-6-sol", withNone, "none", .acceptedOnlyAtLevels(["none"])),
      profile("gpt-6-astra", withoutNone, "low", .rejected),
      profile("gpt-6.1-sol", withoutNone, "low", .rejected),
    ]
  }()

  /// Claude models listed on the Effort page (research R3). `low` is the
  /// lowest level every one of them supports. Temperature is dropped for the
  /// whole kind (`kindsWithoutTemperature`); `.rejected` records why. Models
  /// without effort support (Haiku 4.5, Sonnet 4.5) have no profile: one would
  /// change nothing.
  private static let anthropic: [ModelProfile] = {
    let full = ["low", "medium", "high", "xhigh", "max"]
    let noXhigh = ["low", "medium", "high", "max"]
    func profile(_ id: String, _ supported: [String]) -> ModelProfile {
      ModelProfile(
        kind: .anthropic, modelID: id, reasoning: .levels(supported: supported, preferred: "low"),
        temperature: .rejected, source: anthropicSource)
    }
    return [
      profile("claude-fable-5-1", full),
      profile("claude-mythos-5-1", full),
      profile("claude-fable-5", full),
      profile("claude-mythos-5", full),
      profile("claude-mythos-preview", noXhigh),
      profile("claude-opus-5-5", full),
      profile("claude-opus-5", full),
      profile("claude-opus-4-8", full),
      profile("claude-opus-4-7", full),
      profile("claude-opus-4-6", noXhigh),
      profile("claude-opus-4-5", ["low", "medium", "high"]),
      profile("claude-sonnet-5-5", full),
      profile("claude-sonnet-5", full),
      profile("claude-sonnet-4-6", noXhigh),
      profile("claude-haiku-5-5", full),
    ]
  }()

  /// Gemini models (research R4). `minimal` returns an error on 3.8 Flash and
  /// 4 Argon, so they prefer `low`. Google says to remove `temperature` for
  /// all 3.x models and that 4 ignores it, hence `.discouraged`. Deprecated
  /// IDs routed to a successor (3.7 Flash to 3.8, 3.5 Flash to 3.6) mirror the
  /// model that actually answers. Gemini 2.5 takes `thinkingBudget` instead of
  /// a level. Not profiled: 2.5 Flash-Lite (does not think by default) and
  /// preview models other than the two listed (FR-003).
  private static let gemini: [ModelProfile] = {
    let withMinimal = ["minimal", "low", "medium", "high"]
    let withoutMinimal = ["low", "medium", "high"]
    func level(_ id: String, _ supported: [String], _ preferred: String) -> ModelProfile {
      ModelProfile(
        kind: .gemini, modelID: id,
        reasoning: .levels(supported: supported, preferred: preferred),
        temperature: .discouraged, source: geminiSource)
    }
    func budget(_ id: String, _ range: ClosedRange<Int>, _ preferred: Int) -> ModelProfile {
      ModelProfile(
        kind: .gemini, modelID: id, reasoning: .thinkingBudget(range: range, preferred: preferred),
        temperature: .accepted, source: geminiSource)
    }
    return [
      level("gemini-4-argon", withoutMinimal, "low"),
      level("gemini-3.8-flash", withoutMinimal, "low"),
      level("gemini-3.7-flash", withoutMinimal, "low"),
      level("gemini-3.6-flash", withMinimal, "minimal"),
      level("gemini-3.5-flash", withMinimal, "minimal"),
      level("gemini-3.5-flash-lite", withMinimal, "minimal"),
      level("gemini-3.1-flash-lite", withMinimal, "minimal"),
      level("gemini-3-flash-preview", withMinimal, "minimal"),
      // Thinking levels for this model are not in Google's table, so only its
      // temperature rule is recorded.
      ModelProfile(
        kind: .gemini, modelID: "gemini-3.1-pro-preview", reasoning: nil,
        temperature: .discouraged, source: geminiSource),
      budget("gemini-2.5-pro", 128...32768, 128),
      budget("gemini-2.5-flash", 0...24576, 0),
    ]
  }()
}
