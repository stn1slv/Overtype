# Setting Up Your OpenAI API Key

Overtype uses OpenAI's API to perform text transformations (like grammar correction, translation, or rewriting). Because Overtype runs entirely locally on your Mac, you need to provide your own API key.

## 1. Generate an OpenAI API Key

1. Go to the [OpenAI Developer Platform](https://platform.openai.com/).
2. Log in or create an account.
3. In the left sidebar, navigate to **API keys**.
4. Click the **"Create new secret key"** button.
5. Give it a memorable name (e.g., "Overtype Mac App").
6. Click **Create secret key**.
7. **Copy the key** immediately. (It will look something like `sk-proj-...`). You won't be able to see it again after closing the window.

*Note: You must have a funded billing account (or available credits) in OpenAI for the API to work. ChatGPT Plus subscriptions do not cover API usage.*

## 2. Save the Key Securely in Overtype

Overtype values your privacy and security. API keys are **never** stored in plaintext configuration files. Instead, they are saved securely to your Mac's native Keychain.

1. Launch **Overtype**.
2. Click the **Overtype icon** (the quotation mark `”`) in your Mac menu bar.
3. Select **Settings...** from the dropdown menu.
4. In the Settings window, locate the **OpenAI API Key** field.
5. **Paste** your `sk-...` API key into the secure text field.
6. Click **Save**.

macOS will immediately encrypt and store the key in your system Keychain under the identifier `overtype-openai-key`. 

*(Note: If you ever open the macOS "Passwords" or "Keychain Access" app, you will see a generic password entry named `overtype-openai-key`. This is completely normal and expected).*

## 3. Verify Your Configuration

Once your key is saved in the UI, ensure your `config.json` (located at `~/Library/Application Support/Overtype/config.json`) is pointing to the correct Keychain identifier.

By default, the provider configuration should look exactly like this:

```json
"providers": [
  {
    "id": "openai",
    "kind": "openai",
    "baseURL": "https://api.openai.com/v1",
    "defaultModel": "gpt-4o-mini",
    "timeoutSeconds": 30.0,
    "retryDelaySeconds": 0.5,
    "keychainKey": "overtype-openai-key"
  }
]
```

### How it works:
When you press your global shortcut (e.g., `⌃⌥⌘G`), the Overtype Action Engine checks your `config.json` for the provider. It sees `"keychainKey": "overtype-openai-key"`, securely extracts your API key from the macOS Keychain, makes the request to OpenAI in memory, and immediately discards the key when the request finishes.
