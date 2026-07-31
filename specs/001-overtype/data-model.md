# Data Model: Overtype (Reword)

## Application Configuration Models

These models are serialized as JSON in `~/Library/Application Support/Reword/config.json`.

### `AppConfig`
Root configuration structure.
- `version: Int` (Schema version, currently 1)
- `providers: [ProviderConfig]`
- `actions: [ActionConfig]`
- `general: GeneralConfig`

### `ProviderConfig`
Configuration for an AI Provider.
- `id: String` (Unique identifier, e.g., "openai-main")
- `kind: ProviderKind` (Enum: `.openAICompatible`, `.anthropic`, `.ollama`)
- `baseURL: String`
- `defaultModel: String`
- `keychainAccount: String?` (Account name in keychain for API key, nil if none)
- `timeoutSeconds: Double`
- `extraHeaders: [String: String]`

### `ActionConfig`
Configuration for a text transformation action.
- `id: String` (Unique identifier)
- `title: String` (Display name)
- `enabled: Bool`
- `shortcut: ShortcutConfig?`
- `providerID: String` (Links to `ProviderConfig.id`)
- `model: String?`
- `systemPrompt: String`
- `userPromptTemplate: String` (Must contain `{{text}}`)
- `temperature: Double`
- `maxInputCharacters: Int`
- `allowNewlines: Bool`
- `writeStrategy: WriteStrategy` (Enum: `.typing`, `.accessibility`, `.auto`)

### `ShortcutConfig`
- `keyCode: UInt16`
- `modifiers: UInt32`
- `displayString: String`

### `GeneralConfig`
- `showHUD: Bool`
- `playSounds: Bool`
- `typingChunkSize: Int`
- `typingDelayMicroseconds: UInt32`
- `deliveryMethod: DeliveryMethod` (Enum: `.hidTap`, `.sessionTap`, `.directToPid`, `.hidSlow`)
- `focusRetryAttempts: Int`
- `focusRetryIntervalMs: Int`
- `logLevel: LogLevel` (Enum: `.info`, `.debug`, etc.)

## Application State Models

### `Selection`
Represents the text read from the frontmost application.
- `text: String` (The selected text)
- `element: AXUIElement` (Reference to the UI element)
- `range: CFRange?` (Text range if available)
- `appName: String` (Name of the application)
- `bundleID: String` (Bundle ID of the application)
- `pid: pid_t` (Process ID)

### `TransformRequest`
Payload passed to `AIProvider`.
- `systemPrompt: String`
- `userPrompt: String`
- `model: String`
- `temperature: Double`
- `timeout: TimeInterval`
