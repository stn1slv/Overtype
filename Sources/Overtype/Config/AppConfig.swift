import AppKit
import KeyboardShortcuts

/// Collects notes about configuration values the tolerant decoder dropped or
/// replaced with defaults, so the load can warn instead of failing or staying
/// silent (finding C3; Principle VI). Reference type on purpose: decoders can
/// only reach shared state through `Decoder.userInfo`, which carries values.
/// Issue text names keys, ids, and indices only, never the offending values,
/// because config.json holds user-authored prompts (Principle V).
public final class ConfigDecodingIssues {
  public private(set) var issues: [String] = []

  public init() {}

  public func record(_ issue: String) {
    issues.append(issue)
  }

  /// `CodingUserInfoKey(rawValue:)` is failable in signature only (a non-empty
  /// literal cannot fail); stored as optional to avoid a forbidden force unwrap.
  static let userInfoKey = CodingUserInfoKey(rawValue: "overtypeConfigDecodingIssues")

  public static func attach(_ issues: ConfigDecodingIssues, to decoder: JSONDecoder) {
    guard let key = userInfoKey else { return }
    decoder.userInfo[key] = issues
  }

  static func from(_ decoder: Decoder) -> ConfigDecodingIssues? {
    guard let key = userInfoKey else { return nil }
    return decoder.userInfo[key] as? ConfigDecodingIssues
  }
}

/// Decodes a field that has a safe fallback: both absence and an unreadable
/// (wrong-typed) value fall back to it, recording an issue in the latter case.
/// Tolerance for fields with defaults is what keeps one hand-edited typo from
/// costing the whole configuration (finding C3).
func tolerantDecode<V: Decodable, K: CodingKey>(
  _ container: KeyedDecodingContainer<K>, key: K, default fallback: V,
  context: String, decoder: Decoder
) -> V {
  do {
    return try container.decodeIfPresent(V.self, forKey: key) ?? fallback
  } catch {
    ConfigDecodingIssues.from(decoder)?.record(
      "\(context).\(key.stringValue): unreadable value replaced by default")
    return fallback
  }
}

/// Wraps one array element so a broken element fails alone instead of failing
/// the whole array (finding C3). Captures the element's `id` when readable so
/// the load warning can name what was dropped.
struct FailableConfigElement<T: Decodable>: Decodable {
  let value: T?
  let failedID: String?

  private struct IDProbe: Decodable {
    let id: String?
  }

  init(from decoder: Decoder) throws {
    if let decoded = try? T(from: decoder) {
      value = decoded
      failedID = nil
    } else {
      value = nil
      failedID = (try? IDProbe(from: decoder))?.id
    }
  }
}

/// The root configuration object loaded from config.json
public struct AppConfig: Codable, Equatable {
  public var global: GeneralConfig
  public var providers: [ProviderConfig]
  public var actions: [ActionConfig]

  public init(global: GeneralConfig, providers: [ProviderConfig], actions: [ActionConfig]) {
    self.global = global
    self.providers = providers
    self.actions = actions
  }

  // Tolerant decoding: a hand-edited config.json that omits a section, holds a
  // wrong-typed value, or contains one broken provider/action must not fail the
  // whole decode, because ConfigStore would then fall back to the default
  // config and the next save would overwrite the user's file (finding C3).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let issues = ConfigDecodingIssues.from(decoder)

    global = tolerantDecode(
      container, key: .global, default: GeneralConfig(), context: "config", decoder: decoder)

    let providerElements = tolerantDecode(
      container, key: .providers, default: [FailableConfigElement<ProviderConfig>](),
      context: "config", decoder: decoder)
    providers = providerElements.compactMap { $0.value }
    for (index, element) in providerElements.enumerated() where element.value == nil {
      issues?.record("providers[\(element.failedID ?? String(index))]: unreadable entry dropped")
    }

    let actionElements = tolerantDecode(
      container, key: .actions, default: [FailableConfigElement<ActionConfig>](),
      context: "config", decoder: decoder)
    actions = actionElements.compactMap { $0.value }
    for (index, element) in actionElements.enumerated() where element.value == nil {
      issues?.record("actions[\(element.failedID ?? String(index))]: unreadable entry dropped")
    }
  }
}

public struct GeneralConfig: Codable, Equatable {
  public var typingSpeedMultiplier: Double
  public var showHUD: Bool
  public var typingChunkSize: Int?
  public var typingDelayMicroseconds: Int?
  /// Per-app typing overrides keyed by bundle identifier. Web/Chromium editors
  /// (e.g. new Outlook) apply synthetic keystrokes asynchronously and reorder them
  /// under a fast burst, so they need a slower, verified cadence than the default.
  public var appTypingOverrides: [String: AppTypingOverride]?

  public init(
    typingSpeedMultiplier: Double = 1.0, showHUD: Bool = true, typingChunkSize: Int? = 20,
    typingDelayMicroseconds: Int? = 2000, appTypingOverrides: [String: AppTypingOverride]? = nil
  ) {
    self.typingSpeedMultiplier = typingSpeedMultiplier
    self.showHUD = showHUD
    self.typingChunkSize = typingChunkSize
    self.typingDelayMicroseconds = typingDelayMicroseconds
    self.appTypingOverrides = appTypingOverrides
  }

  // Tolerant decoding: fields with a natural default fall back to it on absence
  // AND on a wrong-typed value instead of failing the decode of the whole
  // config (see AppConfig.init(from:); finding C3).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    typingSpeedMultiplier = tolerantDecode(
      container, key: .typingSpeedMultiplier, default: 1.0, context: "global", decoder: decoder)
    showHUD = tolerantDecode(
      container, key: .showHUD, default: true, context: "global", decoder: decoder)
    typingChunkSize = tolerantDecode(
      container, key: .typingChunkSize, default: Int?.none, context: "global", decoder: decoder)
    typingDelayMicroseconds = tolerantDecode(
      container, key: .typingDelayMicroseconds, default: Int?.none, context: "global",
      decoder: decoder)
    appTypingOverrides = tolerantDecode(
      container, key: .appTypingOverrides, default: [String: AppTypingOverride]?.none,
      context: "global", decoder: decoder)
  }
}

/// Overrides the typing cadence for a specific application. Either field is optional;
/// a nil field falls back to the corresponding global `GeneralConfig` value.
public struct AppTypingOverride: Codable, Equatable {
  public var typingChunkSize: Int?
  public var typingDelayMicroseconds: Int?

  public init(typingChunkSize: Int? = nil, typingDelayMicroseconds: Int? = nil) {
    self.typingChunkSize = typingChunkSize
    self.typingDelayMicroseconds = typingDelayMicroseconds
  }
}

public enum ProviderKind: String, Codable, Equatable {
  case openAICompatible = "openai"
  case anthropic = "anthropic"
  case ollama = "ollama"
  case gemini = "gemini"
}

public struct ProviderConfig: Codable, Equatable {
  /// Single source for the retry-pause default, shared by the memberwise init,
  /// the tolerant decoder, the Providers tab form, and `ActionEngine`'s
  /// fallback, so the four cannot drift apart.
  public static let defaultRetryDelaySeconds: Double = 0.5

  public var id: String
  public var kind: ProviderKind
  public var baseURL: URL?
  public var defaultModel: String
  public var timeoutSeconds: Double
  /// Pause before the single automatic retry of a transient provider failure
  /// (see `ProviderError.isRetryable`). Gives a rate limit a chance to clear
  /// before the second attempt. `0` retries immediately.
  public var retryDelaySeconds: Double
  // keychainKey references a generic password in the macOS Keychain
  public var keychainKey: String?

  public init(
    id: String, kind: ProviderKind, baseURL: URL? = nil, defaultModel: String,
    timeoutSeconds: Double = 30.0,
    retryDelaySeconds: Double = ProviderConfig.defaultRetryDelaySeconds,
    keychainKey: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.baseURL = baseURL
    self.defaultModel = defaultModel
    self.timeoutSeconds = timeoutSeconds
    self.retryDelaySeconds = retryDelaySeconds
    self.keychainKey = keychainKey
  }

  // Tolerant decoding: `id`, `kind`, and `defaultModel` stay required (a provider
  // without them is unusable; a failure here drops only this element, see
  // FailableConfigElement); everything else has a safe fallback.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(ProviderKind.self, forKey: .kind)
    defaultModel = try container.decode(String.self, forKey: .defaultModel)

    // baseURL is decoded as a string and parsed here: letting URL's own
    // Decodable throw on a hand-edited value would abort the whole decode
    // (finding C3). An unparseable value degrades to nil and the provider
    // fails later with the existing typed URL error.
    let urlString = tolerantDecode(
      container, key: .baseURL, default: String?.none, context: "provider '\(id)'",
      decoder: decoder)
    if let urlString = urlString {
      if let parsed = URL(string: urlString), parsed.scheme != nil {
        baseURL = parsed
      } else {
        ConfigDecodingIssues.from(decoder)?.record(
          "provider '\(id)'.baseURL: not a valid URL; ignored")
        baseURL = nil
      }
    } else {
      baseURL = nil
    }

    timeoutSeconds = tolerantDecode(
      container, key: .timeoutSeconds, default: 30.0, context: "provider '\(id)'",
      decoder: decoder)
    // Absent in configs written before the retry feature; those keep the 0.5s
    // default rather than failing to decode.
    retryDelaySeconds = tolerantDecode(
      container, key: .retryDelaySeconds, default: ProviderConfig.defaultRetryDelaySeconds,
      context: "provider '\(id)'", decoder: decoder)
    keychainKey = tolerantDecode(
      container, key: .keychainKey, default: String?.none, context: "provider '\(id)'",
      decoder: decoder)
  }
}

public enum WriteStrategy: String, Codable, Equatable {
  case typing = "typing"
}

public struct ActionShortcut: Codable, Equatable {
  public var keyCode: Int
  public var modifiers: Int
  public var displayString: String

  public init(keyCode: Int, modifiers: Int, displayString: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.displayString = displayString
  }

  // Tolerant decoding: `displayString` is cosmetic, so its absence must not
  // drop the whole action (finding C3). `keyCode`/`modifiers` stay required;
  // a wrong type here fails only the shortcut, which the action-level decode
  // degrades to "no shortcut" with a recorded issue.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try container.decode(Int.self, forKey: .keyCode)
    modifiers = try container.decode(Int.self, forKey: .modifiers)
    displayString = try container.decodeIfPresent(String.self, forKey: .displayString) ?? ""
  }

  /// Nil when the stored values cannot form a valid shortcut. config.json is a
  /// documented hand-editing surface, and `UInt(_:)` traps on a negative Int,
  /// which turned a bad `modifiers` value into a crash at every launch, before
  /// the status item existed, with no in-app recovery (finding C1). Callers
  /// must skip a nil shortcut and warn instead of registering it.
  public var keyboardShortcut: KeyboardShortcuts.Shortcut? {
    guard keyCode >= 0, modifiers >= 0 else { return nil }
    return KeyboardShortcuts.Shortcut(
      KeyboardShortcuts.Key(rawValue: keyCode),
      modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    )
  }
}

public struct ActionConfig: Codable, Equatable {
  public var id: String
  public var title: String
  public var enabled: Bool
  public var shortcut: ActionShortcut?

  public var providerID: String
  public var model: String?  // Overrides provider default if set

  public var systemPrompt: String
  public var userPromptTemplate: String
  public var temperature: Double

  public var maxInputCharacters: Int
  public var allowNewlines: Bool
  public var writeStrategy: WriteStrategy

  public init(
    id: String, title: String, enabled: Bool, shortcut: ActionShortcut? = nil, providerID: String,
    model: String? = nil, systemPrompt: String, userPromptTemplate: String,
    temperature: Double = 0.0, maxInputCharacters: Int = 5000, allowNewlines: Bool = false,
    writeStrategy: WriteStrategy = .typing
  ) {
    self.id = id
    self.title = title
    self.enabled = enabled
    self.shortcut = shortcut
    self.providerID = providerID
    self.model = model
    self.systemPrompt = systemPrompt
    self.userPromptTemplate = userPromptTemplate
    self.temperature = temperature
    self.maxInputCharacters = maxInputCharacters
    self.allowNewlines = allowNewlines
    self.writeStrategy = writeStrategy
  }

  // Tolerant decoding: identity, provider reference, and the prompts stay
  // required (an action without them is unusable; a failure there drops only
  // this element, see FailableConfigElement); everything else falls back on
  // absence and on a wrong-typed value alike (finding C3).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    providerID = try container.decode(String.self, forKey: .providerID)
    systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
    userPromptTemplate = try container.decode(String.self, forKey: .userPromptTemplate)

    enabled = tolerantDecode(
      container, key: .enabled, default: true, context: "action '\(id)'", decoder: decoder)
    shortcut = tolerantDecode(
      container, key: .shortcut, default: ActionShortcut?.none, context: "action '\(id)'",
      decoder: decoder)
    model = tolerantDecode(
      container, key: .model, default: String?.none, context: "action '\(id)'", decoder: decoder)
    temperature = tolerantDecode(
      container, key: .temperature, default: 0.0, context: "action '\(id)'", decoder: decoder)
    maxInputCharacters = tolerantDecode(
      container, key: .maxInputCharacters, default: 5000, context: "action '\(id)'",
      decoder: decoder)
    allowNewlines = tolerantDecode(
      container, key: .allowNewlines, default: false, context: "action '\(id)'", decoder: decoder)
    writeStrategy = tolerantDecode(
      container, key: .writeStrategy, default: .typing, context: "action '\(id)'",
      decoder: decoder)
  }
}
