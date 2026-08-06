# Privacy & Security Model

Overtype is architected explicitly for privacy-conscious organizations.

## Clipboard Isolation

The core tenet of Overtype is the absolute isolation from the macOS Pasteboard (`NSPasteboard`). 

Why? Modern enterprise environments use strict MDM policies, DLP (Data Loss Prevention) software, and clipboard managers that flag or prevent background applications from reading the user's copied text. By utilizing the macOS Accessibility APIs (`kAXSelectedTextAttribute`) to read text, and synthetic `CGEvent` keyboard events to type it back, Overtype operates identically to a user physically typing on a keyboard.

## Logging and Telemetry

- **No Remote Telemetry**: Overtype does not track analytics, product usage, or crash telemetry to any remote server.
- **Log Sanitization**: Local unified logs (accessible via Console.app) redact the actual text processed by default (e.g. `<redacted 12 chars>`). Verbose text logging is only enabled if the user explicitly toggles a Debug mode.

## Network Requests

Network calls are made exclusively to the endpoints configured by the user in `config.json`.
For OpenAI, the request is sent directly from your machine to `api.openai.com`. There are no intermediary servers or proxies.

When you invoke a **Google Gemini** action, the selected text is sent directly from your machine to Google's Gemini endpoint (`generativelanguage.googleapis.com`) and nowhere else. The Gemini API key is read from the macOS Keychain and sent in the `x-goog-api-key` request header; it is never placed in the request URL, written to `config.json`, or logged.

When you invoke an **Anthropic Claude** action, the selected text is sent directly from your machine to Anthropic's Messages endpoint (`api.anthropic.com`) and nowhere else. The Anthropic API key is read from the macOS Keychain and sent in the `x-api-key` request header; it is never placed in the request URL, written to `config.json`, or logged. If the model declines a request, Anthropic returns a short reason category (for example `cyber`) alongside a longer prose explanation — Overtype reports only the category, and deliberately discards the explanation, because that server-authored text can echo fragments of what you submitted.

## Credential Storage

API keys are not stored in plaintext configuration files. They are placed in the secure macOS Keychain using `kSecClassGenericPassword`.
