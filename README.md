# Overtype (Overtype)

Overtype is a native, lightweight macOS menu bar utility that applies AI-powered transformations (like grammar correction) directly to text you're typing in *any* application.

It securely modifies text via macOS Accessibility APIs, completely bypassing the system clipboard to ensure maximum privacy and compliance with enterprise security policies.

## Features

- **Clipboard Isolation**: Overtype never touches `NSPasteboard`. It reads and types text strictly through the macOS Accessibility API (`AXUIElement` & `CGEvent`).
- **AI Integrations**: Natively supports OpenAI (like GPT-4o-mini). (Anthropic and Ollama support coming soon).
- **Global Hotkeys**: Highlight text in any application (like MS Teams or Apple Notes), hit a shortcut (e.g. ⌃⌥⌘G), and watch the text get magically replaced inline.
- **Privacy First**: Sensitive text is never written to disk. Only standard, sanitized application logs are recorded.

## Setup

1. **Build the Application**:
   ```bash
   ./scripts/build-app.sh
   ```
2. **Launch**:
   Open the generated bundle `Overtype.app` inside the `.build/release/` directory.
3. **Accessibility Permissions**:
   On first launch, macOS will prompt you to grant Accessibility permissions in System Settings > Privacy & Security > Accessibility. This is required for Overtype to read the focused text field.
4. **Configuration**:
   Click the `Overtype` menu bar icon, open **Settings**, and paste your OpenAI API key.

## Configuration file

You can manage your actions, hotkeys, and AI templates via the JSON configuration file stored at `~/Library/Application Support/Overtype/config.json`.

```json
{
  "actions": [
    {
      "id": "fix-grammar",
      "title": "Fix grammar",
      "enabled": true,
      "shortcut": { "keyCode": 5, "modifiers": 1835008, "displayString": "⌃⌥⌘G" },
      "providerID": "openai",
      "systemPrompt": "You are a proofreader. Fix grammar, spelling, and punctuation...",
      "userPromptTemplate": "{{text}}"
    }
  ]
}
```

## Security & Privacy Constraints

- **No Clipboard**: The system pasteboard (`NSPasteboard`) is strictly avoided to prevent triggering clipboard monitoring tools or leaking secrets.
- **Destructive Isolation**: Overtype only edits text that is actively selected. It will not blindly delete and retype text if the user loses focus.
- **Keychain Storage**: API keys are stored securely using macOS Keychain (`kSecClassGenericPassword`), never in plaintext JSON.

## License

MIT License.
