# Overtype

Overtype is a native, lightweight macOS menu bar utility that applies AI-powered transformations (like grammar correction) directly to text you select in *any* application.

It securely modifies text via macOS Accessibility APIs, completely bypassing the system clipboard to ensure maximum privacy and compliance with enterprise security policies.

## Features

- **Clipboard Isolation**: Overtype never touches `NSPasteboard`. It reads and types text strictly through the macOS Accessibility API (`AXUIElement` & `CGEvent`).
- **AI Integrations**: Natively supports OpenAI (like GPT-5.4-nano), Google Gemini, and Anthropic Claude. (Ollama support coming soon).
- **Global Hotkeys**: Highlight text in any application (like MS Teams or Apple Notes), hit a shortcut (e.g. ⌃⌥⌘G), and watch the text get magically replaced inline.
- **Privacy First**: By default, sensitive text is never written to disk; only standard, sanitized application logs are recorded. Unredacted text is logged only if you explicitly enable debug logging.

## Installation

### Via Homebrew (Recommended)

You can easily install Overtype using our custom Homebrew tap:

```bash
brew install stn1slv/tap/overtype
```

Homebrew prints these notes after installing and after every upgrade; they are
repeated here because both are easy to hit.

**First launch may be blocked.** Overtype is ad-hoc signed and not notarized, so
Gatekeeper can refuse to open it. Remove the quarantine attribute and try again:

```bash
xattr -dr com.apple.quarantine "/Applications/Overtype.app"
```

**Accessibility permission must be re-granted after every upgrade.** macOS ties
the permission to the app's code signature, and an ad-hoc signature changes with
every build, so an upgraded copy is a different app as far as the system is
concerned. The catch is that the old entry stays in the list and stays enabled,
so nothing looks wrong while Overtype silently fails to read your selection. In
**System Settings > Privacy & Security > Accessibility**, select Overtype,
remove it with the `-` button, then add the upgraded app and enable it.

Both go away if the app is ever signed with an Apple Developer ID certificate
and notarized.

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
      "retryDelaySeconds": 0.5,
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

### Using Google Gemini

Overtype talks to Google Gemini natively (it calls the Gemini `generateContent`
API directly; your text is never sent to any intermediary). Enabling it is pure
configuration, no rebuild required.

1. Get a Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey).

2. Add a Gemini provider block to the `"providers"` array in
   `~/Library/Application Support/Overtype/config.json`:

   ```json
   {
     "id": "gemini",
     "kind": "gemini",
     "defaultModel": "gemini-3.5-flash-lite",
     "timeoutSeconds": 30.0,
     "retryDelaySeconds": 0.5,
     "keychainKey": "overtype-gemini-key"
   }
   ```

   The `"baseURL"` may be omitted; Overtype defaults to
   `https://generativelanguage.googleapis.com/v1beta/`.

3. Store your key in the macOS Keychain under the exact `keychainKey` name.
   Adding the provider through Settings → Providers does this for you; the
   Terminal command below is the manual equivalent if you are editing
   `config.json` by hand:

   ```sh
   security add-generic-password -a "overtype-gemini-key" -w "YOUR_GEMINI_API_KEY" -U
   ```

   The `-a` (account) value must match `keychainKey` exactly — Overtype looks the
   item up by account, not by service.

4. Point an action at the provider by setting its `"providerID"` to `"gemini"`
   (optionally set a per-action `"model"` to override the default). The key is
   sent in the `x-goog-api-key` request header and never written to
   `config.json`, logs, or the URL.

The shipped default configuration does not include a Gemini provider, so a fresh
install adds no extra provider or shortcut until you add the block above.

### Using Anthropic Claude

Overtype talks to Anthropic natively (it calls the Messages API directly; your
text is never sent to any intermediary). You can add it from **Settings →
Providers**, where "Anthropic" now appears in the Kind picker, or by editing
configuration directly. Either way, no rebuild is required.

1. Get an API key from the [Anthropic Console](https://console.anthropic.com/settings/keys).

2. Add an Anthropic provider block to the `"providers"` array in
   `~/Library/Application Support/Overtype/config.json`:

   ```json
   {
     "id": "anthropic",
     "kind": "anthropic",
     "defaultModel": "claude-haiku-4-5",
     "timeoutSeconds": 30.0,
     "retryDelaySeconds": 0.5,
     "keychainKey": "overtype-anthropic-key"
   }
   ```

   The `"baseURL"` may be omitted; Overtype defaults to
   `https://api.anthropic.com/v1/`.

   `claude-haiku-4-5` is recommended as the default because Overtype rewrites a
   selection inline while you wait, so speed matters more than raw capability
   here. Any Claude model works — set a heavier one per action if you want.

3. Store your key in the macOS Keychain under the exact `keychainKey` name.
   Adding the provider through Settings → Providers does this for you; the
   Terminal command below is the manual equivalent if you are editing
   `config.json` by hand:

   ```sh
   security add-generic-password -a "overtype-anthropic-key" -w "YOUR_ANTHROPIC_API_KEY" -U
   ```

   The `-a` (account) value must match `keychainKey` exactly — Overtype looks the
   item up by account, not by service.

   > **Approve the Keychain prompt before your first real run.** An item created
   > this way trusts no application, so the first time Overtype reads it macOS
   > shows an authorization dialog. That dialog takes keyboard focus, which
   > destroys your text selection and aborts the run. Trigger the action once on
   > throwaway text, choose **Always Allow**, and subsequent runs are silent.
   > Keys added through Settings → Providers are written by Overtype itself and
   > never show this prompt.

4. Point an action at the provider by setting its `"providerID"` to `"anthropic"`
   (optionally set a per-action `"model"` to override the default). The key is
   sent in the `x-api-key` request header and never written to `config.json`,
   logs, or the URL.

> **Note:** an action's `"temperature"` is **ignored** for Anthropic runs.
> Newer Claude models (the Opus 4.7/4.8, Opus 5, Sonnet 5 and Fable 5
> generation) reject that parameter with an HTTP 400. Older ones such as
> `claude-haiku-4-5` still accept it, but Overtype never sends it to Anthropic
> rather than maintaining a per-model list that would go stale on every release.
> The setting still applies to OpenAI and Gemini providers.

The shipped default configuration does not include an Anthropic provider, so a
fresh install adds no extra provider or shortcut until you add the block above.

## Security & Privacy Constraints

- **No Clipboard**: The system pasteboard (`NSPasteboard`) is strictly avoided to prevent triggering clipboard monitoring tools or leaking secrets.
- **Destructive Isolation**: Overtype only edits text that is actively selected. It will not blindly delete and retype text if the user loses focus.
- **Keychain Storage**: API keys are stored securely using macOS Keychain (`kSecClassGenericPassword`), never in plaintext JSON.

## License

MIT License.
