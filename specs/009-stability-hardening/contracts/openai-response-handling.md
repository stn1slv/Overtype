# Contract: OpenAI-compatible response handling (after H5)

Applies to `ProviderKind.openAICompatible` (`/chat/completions` shape). Brings the
default provider kind to parity with the typed-error behavior already verified for
Gemini, Anthropic, and Ollama.

## Request (unchanged)

POST `<baseURL>/chat/completions` with `model`, `temperature`, `messages`
(system + user). Authorization: `Bearer <keychain value>`.

## Response mapping

Evaluated in order on HTTP 200:

| Response shape | Result |
|---|---|
| `choices[0].message.refusal` non-empty (content may be null) | `ProviderError.responseBlocked(reason:)` with a short category; the raw refusal text is never logged at info+ |
| `choices[0].finish_reason == "content_filter"` | `ProviderError.responseBlocked(reason:)` |
| `choices` empty, `message` missing, or `content` null/non-string with no refusal | `ProviderError.invalidResponse` |
| `content` empty or whitespace-only | `ProviderError.emptyResponse` |
| `content` beginning with a reasoning block (`<think>`/`<thinking>` variants, or bare reasoning closed by a lone terminator, per the shared stripper) | Reasoning block removed; remainder is the result; empty remainder maps to `ProviderError.emptyResponse` |
| Any other `content` string | Returned as the transform result (existing sanitizer runs downstream) |

Non-200 and transport behavior unchanged: `apiError(statusCode:message:)` with
best-effort body extraction; transport errors via `mapTransportError`; one retry per
`isRetryable` (existing contract).

## Credential lookup

| Keychain outcome | Result |
|---|---|
| Key found, non-empty | Header set, request proceeds |
| `itemNotFound` or empty value | `ProviderError.apiKeyMissing`, no log noise |
| Any other Keychain failure | `ProviderError.apiKeyMissing` for the HUD, plus one `.warning` log naming the keychain key and the status label (never the value) |

## Seams (for tests)

`endpointURL(base:)` and `parseResponseText(from:)` are static and pure, mirroring the
other providers; `OpenAICompatibleProviderTests` drives them with recorded response
fixtures for every row above.
