import AppKit
import KeyboardShortcuts

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

  // Tolerant decoding: a hand-edited config.json that omits a section must not
  // fail the whole decode, because ConfigStore would then fall back to the
  // default config and the next save would overwrite the user's file.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    global = try container.decodeIfPresent(GeneralConfig.self, forKey: .global) ?? GeneralConfig()
    providers = try container.decodeIfPresent([ProviderConfig].self, forKey: .providers) ?? []
    actions = try container.decodeIfPresent([ActionConfig].self, forKey: .actions) ?? []
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

  // Tolerant decoding: fields with a natural default fall back to it instead of
  // failing the decode of the whole config (see AppConfig.init(from:)).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    typingSpeedMultiplier =
      try container.decodeIfPresent(Double.self, forKey: .typingSpeedMultiplier) ?? 1.0
    showHUD = try container.decodeIfPresent(Bool.self, forKey: .showHUD) ?? true
    typingChunkSize = try container.decodeIfPresent(Int.self, forKey: .typingChunkSize)
    typingDelayMicroseconds = try container.decodeIfPresent(
      Int.self, forKey: .typingDelayMicroseconds)
    appTypingOverrides = try container.decodeIfPresent(
      [String: AppTypingOverride].self, forKey: .appTypingOverrides)
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
    timeoutSeconds: Double = 30.0, retryDelaySeconds: Double = 0.5, keychainKey: String? = nil
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
  // without them is unusable); everything else has a safe default.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(ProviderKind.self, forKey: .kind)
    baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
    defaultModel = try container.decode(String.self, forKey: .defaultModel)
    timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 30.0
    // Absent in configs written before the retry feature; those keep the 0.5s
    // default rather than failing to decode.
    retryDelaySeconds =
      try container.decodeIfPresent(Double.self, forKey: .retryDelaySeconds) ?? 0.5
    keychainKey = try container.decodeIfPresent(String.self, forKey: .keychainKey)
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

  public var keyboardShortcut: KeyboardShortcuts.Shortcut {
    KeyboardShortcuts.Shortcut(
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
  // required (an action without them is unusable); everything else has a safe
  // default matching the memberwise initializer.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    shortcut = try container.decodeIfPresent(ActionShortcut.self, forKey: .shortcut)
    providerID = try container.decode(String.self, forKey: .providerID)
    model = try container.decodeIfPresent(String.self, forKey: .model)
    systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
    userPromptTemplate = try container.decode(String.self, forKey: .userPromptTemplate)
    temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.0
    maxInputCharacters =
      try container.decodeIfPresent(Int.self, forKey: .maxInputCharacters) ?? 5000
    allowNewlines = try container.decodeIfPresent(Bool.self, forKey: .allowNewlines) ?? false
    writeStrategy =
      try container.decodeIfPresent(WriteStrategy.self, forKey: .writeStrategy) ?? .typing
  }
}
