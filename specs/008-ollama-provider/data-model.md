# Phase 1 Data Model: Local Ollama Model Support

**Feature**: `008-ollama-provider` | **Date**: 2026-08-06

---

## Persisted schema: no change

`Config/AppConfig.swift` is **not modified**. Every field an Ollama provider
needs already exists, including the case in the provider-kind enum:

| Field | Type | Ollama use |
|---|---|---|
| `id` | `String` | Referenced by an action's `providerID` |
| `kind` | `ProviderKind` | `.ollama` — the case already exists (`"ollama"`) |
| `baseURL` | `URL?` | Optional. Omitted → `http://localhost:11434` |
| `defaultModel` | `String` | Required. Recipe uses `llama3.2` |
| `timeoutSeconds` | `Double` | Recipe uses `30`; slider range 5-300 |
| `retryDelaySeconds` | `Double` | Default `0.5`, unchanged |
| `keychainKey` | `String?` | Optional, and **its presence does not imply a credential exists** (see below) |

`ActionConfig` is unchanged. Model resolution stays action `model` → provider
`defaultModel`. `maxInputCharacters` (default 5000) keeps its existing meaning
and is the input bound that `num_ctx = 16384` is sized against.

`Config/DefaultConfig.swift` is unchanged, so a fresh install seeds no Ollama
provider (FR-021).

### `keychainKey` semantics for Ollama

`SettingsViewModel.saveProvider` assigns `keychainKey = "overtype-<slug>-key"`
to every created provider but writes to the Keychain only when the key field was
non-empty. For Ollama this produces a valid, fully supported state:

| State | Meaning | Provider behaviour |
|---|---|---|
| `keychainKey == nil` | Hand-written config, no credential | Send no `Authorization` header |
| `keychainKey` set, Keychain entry absent | Created in Settings with an empty key field | Send no `Authorization` header — **must not** throw `.apiKeyMissing` |
| `keychainKey` set, entry present but empty | Degenerate | Send no `Authorization` header |
| `keychainKey` set, entry present, non-empty | Remote or secured deployment | Send `Authorization: Bearer <value>` |

## Error model: three new cases

`Providers/AIProvider.swift`, `enum ProviderError` gains exactly three cases.
This is the only shared type this feature changes, and it is recorded as
Exception IV-b in `plan.md`.

| Case | Payload | `errorDescription` (shape) | `logLabel` | `isRetryable` |
|---|---|---|---|---|
| `serviceUnreachable(address: String)` | endpoint host from config | names the address and says the service does not appear to be running | `"service unreachable"` | `false` |
| `modelNotAvailable(model: String)` | resolved model name from the request | names the model and says it is not installed locally | `"model not available"` | `false` |
| `inputTooLargeForContext(limit: Int)` | `maxSafePromptTokens` | states the limit (a token estimate, ~characters for Latin/CJK; the action's prompt counts too) and tells the user to select less text | `"input too large for context"` | `false` |

Every payload originates in the user's own configuration or in a compile-time
constant, never in server-authored text or the selection, so `errorDescription`
may include them under Principle V. `logLabel` carries none of them, matching the
existing convention.

Adding cases makes the exhaustive `switch` in `errorDescription`, `logLabel`, and
`isRetryable` fail to compile until each is handled — which is the intended
safety property, not an obstacle. `retryableURLErrorCodes` is **not** modified:
its `.cannotConnectToHost` entry keeps its current meaning for the other three
providers, and the Ollama provider maps that condition to the new permanent case
before `mapTransportError` is reached.

## Runtime types (not persisted)

### `OllamaProvider` (new, `Providers/OllamaProvider.swift`)

Mirrors `AnthropicProvider`'s structure: an ephemeral `URLSession` configured
from `timeoutSeconds`, a `String` default base URL (so the file contains no
force unwrap), and pure logic split into `static` helpers that unit tests drive
without a network.

| Member | Kind | Purpose | Unit-tested |
|---|---|---|---|
| `defaultBaseURLString` | `static let String` | `"http://localhost:11434"` | via `endpointURL` |
| `contextWindowTokens` | `static let Int` | `16384` (R3) | via `requestBody` |
| `maxSafePromptTokens` | `static let Int` | `6000` — the pre-send bound in estimated tokens, FR-010b (R3, R13) | via `checkInputSize` |
| `estimatedTokens(_:)` | `static func` | `utf8.count` — the true token upper bound; measured, see R13 | yes |
| `promptBudget(grantedWindow:)` | `static func` | `min(maxSafePromptTokens, granted / 2)` — the server keeps half the window (R13) | yes |
| `parseContextLength(from:)` | `static func` | reads `model_info.<arch>.context_length` from `/api/show` (R13) | yes |
| `showEndpointURL(base:)` | `static func` | `{base}/api/show` | yes |
| `checkInputSize(systemPrompt:userPrompt:)` | `static func` | throws `inputTooLargeForContext(limit:)` when the composed prompt exceeds the bound | yes |
| `endpointURL(base:)` | `static func` | `{base}/api/chat`, slash-normalised | yes |
| `requestBody(model:systemPrompt:userPrompt:temperature:)` | `static func` | Body per contract; asserts `stream: false`, `num_ctx`, role split | yes |
| `stripLeadingReasoningBlock(_:)` | `static func` | FR-009 layer 2, table in the contract | yes |
| `parseResponseText(from:)` | `static func` | `message.content` only, then layer 2, then empty check | yes |
| `extractErrorMessage(from:)` | `static func` | `{"error": String}`, falling back to the OpenAI extractor | yes |
| `mapTransportFailure(_:address:)` | `static func` | `.cannotConnectToHost` / `.cannotFindHost` → `serviceUnreachable`; everything else, including the transient `.networkConnectionLost`, falls through to the shared mapping | yes |
| `isModelNotFound(status:body:)` | `static func` | 404 + `"not found"` in body | yes |
| `transform(_:)` | `func` | Composes the above; the only member touching the network | no (boundary) |

### Data flow for one run

```
ActionEngine.run(action:)
  → SelectionReader                     (unchanged)
  → size check vs maxInputCharacters    (unchanged; refuses, never truncates)
  → ProviderRegistry.provider(for:)     (+1 line: .ollama → OllamaProvider)
  → OllamaProvider.transform            (new)
        checkInputSize                  (FR-010b: refuses before any request)
        POST /api/chat {stream:false, options:{temperature, num_ctx:16384}}
        → message.content
        → stripLeadingReasoningBlock
        → non-empty check
  → ResponseSanitizer                   (unchanged, shared)
  → context re-check (pid + AXUIElement) (unchanged)
  → TextWriter                          (unchanged)
```

No stage before the write is added or reordered, so Principle II holds by
construction: every Ollama failure throws before `TextWriter` is reached.

## Configuration example (documentation only)

```json
{
  "id": "ollama-local",
  "kind": "ollama",
  "defaultModel": "llama3.2",
  "timeoutSeconds": 30
}
```

`baseURL` and `keychainKey` are omitted on purpose: the first falls back to the
documented local address, the second means no credential is sent.
