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

When you invoke an **Ollama** action, the selected text is sent to the endpoint configured on that provider and nowhere else. In the documented setup that endpoint is `http://localhost:11434` — a service running on your own Mac — so **the text never leaves your machine**. This is the one provider where no third party sees your text at all. Overtype's only interaction with the service is the transformation request itself; it never downloads, installs, starts, or stops anything, and it never asks the service to keep a model resident in memory after a run.

By design this means an Ollama run should also work with the machine fully offline. Note that as of 2026-08-06 that is a design property of the code, not yet a recorded test result: the offline run and the traffic observation are acceptance items O10 and O11 in `compatibility.md` and are still pending. What has been verified is the code path — the provider contacts only the configured endpoint, and no telemetry, analytics, or update ping exists anywhere in the application.

Two qualifications, stated plainly. First, this guarantee follows the endpoint, not the provider kind: if you point an Ollama provider at another machine or a hosted deployment, your text goes there instead. Second, no credential is required for a local service, but if you store one for a remote deployment it is read from the macOS Keychain and sent as a bearer token in the `Authorization` header — never in the request URL, `config.json`, or logs. Note that macOS permits plain `http://` to loopback, `.local` names and private LAN addresses, and Overtype will send that bearer token over such a connection in cleartext, where anything on the same network can read it. If you attach a credential to anything other than `localhost`, prefer an `https://` endpoint.

## Credential Storage

API keys are not stored in plaintext configuration files. They are placed in the secure macOS Keychain using `kSecClassGenericPassword`.
