# Overtype

Overtype is a small native macOS menu bar app that runs an AI transformation, such as a grammar fix, on text you select in any application and replaces the selection in place.

It reads and writes text through the macOS Accessibility API and never uses the system clipboard, so it fits environments with strict privacy or security policies.

## Features

- **No clipboard**: Overtype never touches `NSPasteboard`. It reads and types text only through the macOS Accessibility API (`AXUIElement` and `CGEvent`).
- **AI providers**: OpenAI (the default model is `gpt-6-luna`), Google Gemini, Anthropic Claude, and Ollama for models that run locally on your Mac.
- **Global hotkeys**: select text in any application (for example MS Teams or Apple Notes), press a shortcut such as ⌃⌥⌘G, and the selection is replaced inline.
- **Privacy**: by default, selected text is never written to disk and logs are redacted. Unredacted text appears in logs only if you explicitly turn on debug logging.

## Installation

### Homebrew (recommended)

Install Overtype from the Homebrew tap:

```bash
brew install stn1slv/tap/overtype
```

Homebrew prints the two notes below after every install and upgrade. They are repeated here because both problems are easy to run into.

**The first launch may be blocked.** Overtype is ad-hoc signed and not notarized, so Gatekeeper can refuse to open it. Remove the quarantine attribute and try again:

```bash
xattr -dr com.apple.quarantine "/Applications/Overtype.app"
```

**You must grant the Accessibility permission again after every upgrade.** macOS ties the permission to the app's code signature, and an ad-hoc signature changes with every build, so the system treats an upgraded copy as a different app. The old entry stays in the list and stays enabled, so nothing looks wrong while Overtype quietly fails to read your selection. In **System Settings > Privacy & Security > Accessibility**, select Overtype, remove it with the `-` button, then add the upgraded app and enable it.

Both problems go away if the app is ever signed with an Apple Developer ID certificate and notarized.

### Manual installation

1. **Build the app**:
   ```bash
   ./scripts/build-app.sh
   ```
2. **Launch it**: open the generated `Overtype.app` in the repository root, or move it to `/Applications` first.

## Setup

1. **Accessibility permission**: on first launch, macOS asks you to grant the Accessibility permission in System Settings > Privacy & Security > Accessibility. Overtype needs it to read the focused text field.
2. **API key**: click the Overtype menu bar icon (the quotation mark), open **Settings**, and paste your OpenAI API key. Overtype stores the key in your macOS Keychain and never writes it to a plain-text config file. For step-by-step instructions, see the [OpenAI setup guide](docs/openai-setup.md).

## Configuration

You can manage preferences, providers, actions and global hotkeys in the **Settings** window (open it from the menu bar icon). Settings validates each change and writes it to the configuration file at `~/Library/Application Support/Overtype/config.json`. You can also view or edit that file by hand.

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
      "defaultModel": "gpt-6-luna",
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
      "maxInputCharacters": 5000,
      "allowNewlines": false,
      "writeStrategy": "typing"
    }
  ]
}
```

### Typing speed

Overtype types the AI's response with simulated keystrokes. You can tune the typing in the `"global"` block:
- **`typingChunkSize`** (integer, default `20`): the number of UTF-16 characters sent in one keystroke event. Larger chunks insert text much faster.
- **`typingDelayMicroseconds`** (integer, default `2000`): the delay between chunks, in microseconds (the default is 2 ms). If an app drops characters, raise this value.
- **`typingSpeedMultiplier`** (double, default `1.0`): scales the delay between chunks. Values above `1.0` type faster (shorter delay); values below `1.0` type slower.
- **`appTypingOverrides`** (object, optional): typing settings for individual apps, keyed by macOS bundle identifier. Each entry can set `typingChunkSize`, `typingDelayMicroseconds`, or both; a field left out uses the global value. Use it for web or Chromium-based editors (such as the new Outlook) that apply synthetic keystrokes asynchronously and garble the output at the fast default cadence. The default configuration includes a tested profile for the new Outlook (`com.microsoft.Outlook`) that types one character at a time with a 10 ms delay.

### API keys

API keys are never stored in `config.json`. Instead:
1. The provider's configuration names a `"keychainKey"` (for example `"overtype-openai-key"`).
2. When you paste a key into the **Settings** window, Overtype saves it in the **macOS Keychain** under that exact name.
3. At run time, Overtype reads the key from the Keychain.

### Choosing the AI model

Overtype picks the model in this order:
1. **The action's model**: if an action sets a `"model"` key (for example `"model": "gpt-4o-mini"`), that model is used. This lets you use a fast, cheap model for simple tasks and a stronger one for complex rewrites.
2. **The provider's default**: if the action has no model, Overtype uses the provider's `"defaultModel"`.

New OpenAI providers start on `gpt-6-luna`, both in the shipped configuration and in **Settings → Providers → Add**. A model you already configured is never changed.

### Temperature and reasoning effort ("Automatic")

You don't need to know which parameters a model accepts. Overtype has built-in profiles for current OpenAI, Anthropic and Gemini models. With an action's settings on **Automatic** (the default), it sends each model only what that model accepts and picks the fastest reasoning level the model supports, because you are waiting while it rewrites your text. For example, `gpt-6-luna` gets `reasoning_effort: "none"`, `claude-haiku-5-5` gets effort `low`, and `gemini-3.8-flash` gets thinking level `low`.

You can override either setting per action, in the Actions editor or in `config.json`:

- `"temperature"`: a number from 0.0 to 2.0. Leave the key out for Automatic. Overtype does not send it to a model that rejects it, or to a model whose provider says to leave it unset (for example Gemini 3.x), and the editor tells you when that happens.
- `"reasoningEffort"`: the provider's own value: `none`, `minimal`, `low`, `medium`, `high`, `xhigh` or `max` for OpenAI; `low` to `max` for Anthropic; `minimal` to `high` for Gemini. Leave the key out for Automatic. For a model Overtype has a profile for, a value the model does not support is not sent, and Automatic applies instead. Gemini 2.5 models take a thinking budget rather than a level, so a text value is never sent to them. For other models the value is sent as written. Ollama does not use this setting, and the editor does not save one for it.

For an OpenAI model without a profile, Overtype sends only what the action sets. If the API rejects `temperature` or `reasoning_effort` by name and the value was valid (a temperature from 0.0 to 2.0, or an effort from the list above), Overtype retries once without it (the HUD shows "Retrying...") and skips that value for that model until you quit the app. If you change the value, Overtype tries it again. A rejected value outside those ranges, such as a typo, shows up as the API error instead.

### Google Gemini

Overtype calls the Gemini `generateContent` API directly, so your text goes to no intermediary. Enabling it takes only configuration, no rebuild.

1. Get a Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey).

2. Add a Gemini provider block to the `"providers"` array in `~/Library/Application Support/Overtype/config.json`:

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

   You can leave out `"baseURL"`; Overtype then uses `https://generativelanguage.googleapis.com/v1beta/`.

3. Store your key in the macOS Keychain under the exact `keychainKey` name. Adding the provider in Settings → Providers does this for you. If you edit `config.json` by hand, this Terminal command does the same:

   ```sh
   security add-generic-password -a "overtype-gemini-key" -w "YOUR_GEMINI_API_KEY" -U
   ```

   The `-a` (account) value must match `keychainKey` exactly, because Overtype looks the item up by account, not by service.

4. Point an action at the provider by setting its `"providerID"` to `"gemini"`. You can also set a per-action `"model"` to override the default. The key is sent in the `x-goog-api-key` request header and is never written to `config.json`, to logs, or to the URL.

The shipped default configuration has no Gemini provider, so a fresh install adds no provider or shortcut until you add the block above.

### Anthropic Claude

Overtype calls the Anthropic Messages API directly, so your text goes to no intermediary. You can add the provider in **Settings → Providers** (choose "Anthropic" as the Kind) or by editing the configuration. Neither needs a rebuild.

1. Get an API key from the [Anthropic Console](https://console.anthropic.com/settings/keys).

2. Add an Anthropic provider block to the `"providers"` array in `~/Library/Application Support/Overtype/config.json`:

   ```json
   {
     "id": "anthropic",
     "kind": "anthropic",
     "defaultModel": "claude-haiku-5-5",
     "timeoutSeconds": 30.0,
     "retryDelaySeconds": 0.5,
     "keychainKey": "overtype-anthropic-key"
   }
   ```

   You can leave out `"baseURL"`; Overtype then uses `https://api.anthropic.com/v1/`.

   We recommend `claude-haiku-5-5` as the default: Overtype rewrites your selection while you wait, so speed matters more here than raw capability. On Automatic, Overtype sends it effort `low`. Any Claude model works, and you can set a stronger one per action.

3. Store your key in the macOS Keychain under the exact `keychainKey` name. Adding the provider in Settings → Providers does this for you. If you edit `config.json` by hand, this Terminal command does the same:

   ```sh
   security add-generic-password -a "overtype-anthropic-key" -w "YOUR_ANTHROPIC_API_KEY" -U
   ```

   The `-a` (account) value must match `keychainKey` exactly, because Overtype looks the item up by account, not by service.

   > **Approve the Keychain prompt before your first real run.** A Keychain item created this way trusts no application, so the first time Overtype reads it, macOS shows an authorization dialog. That dialog takes keyboard focus, which clears your text selection and stops the run. Run the action once on throwaway text and choose **Always Allow**; later runs show no prompt. Keys added in Settings → Providers are written by Overtype itself and never show this prompt.

4. Point an action at the provider by setting its `"providerID"` to `"anthropic"`. You can also set a per-action `"model"` to override the default. The key is sent in the `x-api-key` request header and is never written to `config.json`, to logs, or to the URL.

> **Note:** Overtype **ignores** an action's `"temperature"` for Anthropic. The newest Claude models reject any non-default value with an HTTP 400, and on Anthropic Overtype gets its speed from effort instead, so it never sends a temperature there. An action's `"reasoningEffort"` does apply.

The shipped default configuration has no Anthropic provider, so a fresh install adds no provider or shortcut until you add the block above.

### Ollama (local models)

Overtype calls the `/api/chat` endpoint of a local [Ollama](https://ollama.com) service directly. This is the one provider where **your text never leaves your Mac**: with the default configuration, the only address Overtype contacts is `localhost`, so a run is designed to work with the machine fully offline. You can add the provider in **Settings → Providers** (choose "Ollama" as the Kind) or by editing the configuration. Neither needs a rebuild.

1. Install Ollama and download a model yourself. Overtype never downloads, installs, starts or stops anything for you:

   ```sh
   brew install ollama     # or download from ollama.com
   ollama serve            # start the service
   ollama pull llama3.2    # about 2 GB
   ```

2. Add an Ollama provider block to the `"providers"` array in `~/Library/Application Support/Overtype/config.json`:

   ```json
   {
     "id": "ollama-local",
     "kind": "ollama",
     "defaultModel": "llama3.2",
     "timeoutSeconds": 30.0,
     "retryDelaySeconds": 0.5
   }
   ```

   You can leave out `"baseURL"`; Overtype then uses `http://localhost:11434`. Set it if your service listens on another port or runs on another machine on your network.

   > Plain `http://` works for `localhost`, a `.local` name, and private LAN addresses (`192.168.x.x`, `10.x.x.x`): macOS App Transport Security exempts local networking (we tested this with the built app). A service on a **public** address must use `https://`, because macOS blocks plain HTTP to a public host and the run fails with a network error.

   We recommend `llama3.2` as the default: Overtype rewrites your selection while you wait, and on a laptop a small, fast model makes the difference between usable and unusable. Any model you have installed works, and you can set a larger one per action.

3. **You don't need an API key.** The block above has no `"keychainKey"`, and the API Key field in Settings is marked optional for this provider, so leave it empty. Enter a key only if you point the provider at a remote or password-protected Ollama deployment. Overtype then stores it in the Keychain and sends it in an `Authorization: Bearer` header, the same scheme the OpenAI-compatible provider uses (Gemini and Anthropic use their own headers). If you switch an existing provider's Kind to Ollama, Overtype discards the key stored for it, so a cloud key is never sent to a local endpoint.

4. Point an action at the provider by setting its `"providerID"` to `"ollama-local"`. You can also set a per-action `"model"` to override the default.

> **Size limit.** Ollama is the only provider with its own input limit. If the prompt is too large for the model, Overtype refuses the request before sending anything and shows an error that says so. Three things set the limit:
>
> - **It is measured in UTF-8 bytes**, about 6,000. For English that is about 6,000 characters; for Chinese, Japanese or Korean it is closer to 2,000, and emoji cost even more. This estimate is not overly cautious: against a real model, 100 CJK characters cost 328 tokens, about one per byte.
> - **The action's system prompt counts too**, not only your selection. The shipped prompt (about 170 characters) leaves plenty of room for a full 5,000-character selection, but an action with a long style guide or few-shot examples leaves less.
> - **A model with a small context window gets a smaller limit.** Overtype asks the service how large your model's window really is and uses half of it, because the other half holds the rewrite. A 2,048-token model therefore allows about 1,024 tokens of prompt, not 6,000.
>
> The limit exists because the model's context window has to hold both your selection *and* its rewrite. Without the limit, the service silently drops part of your text (we measured this), and Overtype would replace your whole selection with a rewrite of only a fragment.

> **The first run after a pause is slower.** Ollama unloads a model after a few idle minutes and reloads it on the next request, which can take several seconds by itself. Overtype deliberately does not ask the service to keep your model loaded, because that would hold gigabytes of memory between runs without telling you. To keep it loaded, use Ollama's own `OLLAMA_KEEP_ALIVE` setting.
>
> With `"timeoutSeconds": 30.0`, a first run on slower hardware or with a large model can hit the time limit and report a timeout. That is expected: run it again once the model is loaded, or raise the provider's time limit (the Settings slider goes up to 300 seconds).

> **Note:** unlike Anthropic, Ollama **does** receive an action's `"temperature"` when the action sets one. The service applies it as a generation option, so every model accepts it. On Automatic, Overtype sends no temperature and the model's own default applies.

The shipped default configuration has no Ollama provider, so a fresh install adds no provider or shortcut until you add the block above.

## Security and privacy

- **No clipboard**: Overtype never uses the system pasteboard (`NSPasteboard`), so it does not trigger clipboard monitoring tools or leak secrets through the clipboard.
- **Only the selection is edited**: Overtype changes only text that is actively selected. If the focus moves away, it does not delete and retype anything.
- **Keychain storage**: API keys are stored in the macOS Keychain (`kSecClassGenericPassword`), never in plain-text JSON.

## License

MIT License.
