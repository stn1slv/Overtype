# Overtype

Overtype is a native, lightweight macOS menu bar utility that applies AI-powered transformations (like grammar correction) directly to text you select in *any* application.

It securely modifies text via macOS Accessibility APIs, completely bypassing the system clipboard to ensure maximum privacy and compliance with enterprise security policies.

## Features

- **Clipboard Isolation**: Overtype never touches `NSPasteboard`. It reads and types text strictly through the macOS Accessibility API (`AXUIElement` & `CGEvent`).
- **AI Integrations**: Natively supports OpenAI (like GPT-5.4-nano). (Anthropic and Ollama support coming soon).
- **Global Hotkeys**: Highlight text in any application (like MS Teams or Apple Notes), hit a shortcut (e.g. ⌃⌥⌘G), and watch the text get magically replaced inline.
- **Privacy First**: By default, sensitive text is never written to disk; only standard, sanitized application logs are recorded. Unredacted text is logged only if you explicitly enable debug logging.

## Installation

### Via Homebrew (Recommended)

You can easily install Overtype using our custom Homebrew tap:

```bash
brew install stn1slv/tap/overtype
```

### Manual Installation

1. **Build the Application**:
   ```bash
   ./scripts/build-app.sh
   ```
2. **Launch**:
   Open the generated bundle `Overtype.app` inside the root directory or move it to `/Applications`.

## Setup

1. **Accessibility Permissions**:
   On first launch, macOS will prompt you to grant Accessibility permissions in System Settings > Privacy & Security > Accessibility. This is required for Overtype to read the focused text field.
2. **API Key Setup**:
   Click the **Overtype** menu bar icon (the quotation mark), open **Settings**, and paste your OpenAI API key. This key is stored securely in your macOS Keychain and is *never* written to plaintext config files. For detailed step-by-step instructions, see our [OpenAI Setup Guide](docs/openai-setup.md).

## Configuration Settings

You can manage all your preferences, providers, actions, and global hotkeys directly from the in-app **Settings** window (available via the menu bar icon). Any changes made in the GUI are automatically validated and written back to the configuration file stored at `~/Library/Application Support/Overtype/config.json`. Advanced users can still view or migrate this file manually.

```json
{
  "global": {
    "typingSpeedMultiplier": 1.0,
    "showHUD": true,
    "typingChunkSize": 20,
    "typingDelayMicroseconds": 2000,
    "appTypingOverrides": {
      "com.microsoft.Outlook": { "typingChunkSize": 1, "typingDelayMicroseconds": 10000 }
    }
  },
  "providers": [
    {
      "id": "openai",
      "kind": "openai",
      "baseURL": "https://api.openai.com/v1",
      "defaultModel": "gpt-5.4-nano",
      "timeoutSeconds": 30.0,
      "keychainKey": "overtype-openai-key"
    }
  ],
  "actions": [
    {
      "id": "fix-grammar",
      "title": "Fix grammar",
      "enabled": true,
      "shortcut": { "keyCode": 5, "modifiers": 1835008, "displayString": "⌃⌥⌘G" },
      "providerID": "openai",
      "model": null,
      "systemPrompt": "You are a proofreader. Fix grammar, spelling, and punctuation...",
      "userPromptTemplate": "{{text}}",
      "temperature": 0.0,
      "maxInputCharacters": 5000,
      "allowNewlines": false,
      "writeStrategy": "typing"
    }
  ]
}
```

### Configuring Typing Speed & Performance

Overtype sends simulated keystrokes to type out the AI's response inline. You can tune the typing performance inside the `"global"` configuration block:
- **`typingChunkSize`** (Integer, default `20`): The number of UTF-16 characters sent in a single keystroke event. Chunking makes text insertion dramatically faster.
- **`typingDelayMicroseconds`** (Integer, default `2000`): The delay in microseconds between sending chunks (the default `2000` is 2 ms). If certain apps drop characters, try increasing this delay.
- **`typingSpeedMultiplier`** (Double, default `1.0`): Scales the effective delay between chunks. Values above `1.0` type faster (shorter delay); values below `1.0` type slower.
- **`appTypingOverrides`** (Object, optional): Per-application typing overrides keyed by macOS bundle identifier. Each entry may set `typingChunkSize` and/or `typingDelayMicroseconds`; any field left out falls back to the global value. Use this for web/Chromium-based editors (such as the new Outlook) that apply synthetic keystrokes asynchronously and corrupt the output at the default fast cadence. The default configuration ships a verified profile for the new Outlook (`com.microsoft.Outlook`) that types one character at a time with a 10 ms delay.

### Configuring the API Key

Because Overtype values privacy and security, API keys are never stored in your `config.json` file. Instead:
1. The provider config defines a `"keychainKey"` (e.g. `"overtype-openai-key"`).
2. When you paste your API key into the Overtype **Settings** window, it saves it securely into the **macOS Keychain** under that exact name.
3. At runtime, the Action Engine dynamically retrieves the key from the Keychain.

### Specifying the AI Model

Overtype resolves the AI model to use in the following order:
1. **Action-level model**: If an action specifies a `"model"` key (e.g. `"model": "gpt-4o-mini"`), it is used. This allows you to use faster/cheaper models for simple tasks and heavier models for complex rewrites.
2. **Provider-level default**: If the action omits the model, Overtype falls back to the `"defaultModel"` specified in the provider's configuration.

## Security & Privacy Constraints

- **No Clipboard**: The system pasteboard (`NSPasteboard`) is strictly avoided to prevent triggering clipboard monitoring tools or leaking secrets.
- **Destructive Isolation**: Overtype only edits text that is actively selected. It will not blindly delete and retype text if the user loses focus.
- **Keychain Storage**: API keys are stored securely using macOS Keychain (`kSecClassGenericPassword`), never in plaintext JSON.

## License

MIT License.
