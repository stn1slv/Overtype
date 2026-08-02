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
}

public struct GeneralConfig: Codable, Equatable {
    public var typingSpeedMultiplier: Double
    public var showHUD: Bool
    public var typingChunkSize: Int?
    public var typingDelayMicroseconds: Int?

    public init(typingSpeedMultiplier: Double = 1.0, showHUD: Bool = true, typingChunkSize: Int? = 20, typingDelayMicroseconds: Int? = 2000) {
        self.typingSpeedMultiplier = typingSpeedMultiplier
        self.showHUD = showHUD
        self.typingChunkSize = typingChunkSize
        self.typingDelayMicroseconds = typingDelayMicroseconds
    }
}

public enum ProviderKind: String, Codable, Equatable {
    case openAICompatible = "openai"
    case anthropic = "anthropic"
    case ollama = "ollama"
}

public struct ProviderConfig: Codable, Equatable {
    public var id: String
    public var kind: ProviderKind
    public var baseURL: URL?
    public var defaultModel: String
    public var timeoutSeconds: Double
    // keychainKey references a generic password in the macOS Keychain
    public var keychainKey: String?
    
    public init(id: String, kind: ProviderKind, baseURL: URL? = nil, defaultModel: String, timeoutSeconds: Double = 30.0, keychainKey: String? = nil) {
        self.id = id
        self.kind = kind
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.timeoutSeconds = timeoutSeconds
        self.keychainKey = keychainKey
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
    public var model: String? // Overrides provider default if set
    
    public var systemPrompt: String
    public var userPromptTemplate: String
    public var temperature: Double
    
    public var maxInputCharacters: Int
    public var allowNewlines: Bool
    public var writeStrategy: WriteStrategy
    
    public init(id: String, title: String, enabled: Bool, shortcut: ActionShortcut? = nil, providerID: String, model: String? = nil, systemPrompt: String, userPromptTemplate: String, temperature: Double = 0.0, maxInputCharacters: Int = 5000, allowNewlines: Bool = false, writeStrategy: WriteStrategy = .typing) {
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
}
