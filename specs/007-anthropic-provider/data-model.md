# Data Model: Anthropic Claude Model Support

**Feature**: `007-anthropic-provider` | **Date**: 2026-08-06

This feature introduces **no new persisted schema**. It reuses the existing
provider record and Keychain storage unchanged. Nothing in `AppConfig.swift`
changes — including `ProviderKind`, whose `anthropic` case already exists.

---

## Configuration entities (existing, reused)

### `ProviderConfig`

| Field | Type | For Anthropic |
|---|---|---|
| `id` | `String` | User-chosen identifier, referenced by an action's `providerID` (e.g. `anthropic`) |
| `kind` | `ProviderKind` | `.anthropic` — **the enum case already exists**; no edit needed |
| `baseURL` | `URL?` | Optional override. When `nil`, the provider uses `https://api.anthropic.com/v1/`. Set it only to route through a proxy |
| `defaultModel` | `String` | `claude-haiku-4-5` in the documented recipe. Used when the action sets no model |
| `timeoutSeconds` | `Double` | Hard timeout, default 30.0. Applied to both the request and resource intervals |
| `retryDelaySeconds` | `Double` | Pause before the single automatic retry, default 0.5. Consumed by `ActionEngine`, not by the provider |
| `keychainKey` | `String?` | Keychain account name holding the API key, e.g. `overtype-anthropic-key`. Never holds the key itself |

**Validation / rules**

- `kind` must decode from the literal string `"anthropic"`. This already works
  today; the gap is registration, not decoding.
- `keychainKey` absent, empty, unreadable, or resolving to an empty string all
  produce `.apiKeyMissing` **before** any network call and therefore before any
  write (FR-012, Principle II).
- `baseURL` is normalised to end in `/` before the `messages` path is appended,
  so both `https://host/v1` and `https://host/v1/` behave identically.
- `defaultModel` is not validated locally. An unrecognised model is reported by
  the service as a 404 and surfaces as `.apiError(404, …)` (FR-010).

### `ActionConfig` (unchanged)

An action names a provider via `providerID` and may override `model`. Model
resolution order is unchanged and provider-agnostic: action `model` if present,
otherwise the provider's `defaultModel`.

The action's `temperature` field is **read but never transmitted** for Anthropic
runs (FR-007). It continues to apply to `openai` and `gemini` providers.

### Anthropic API key (secret)

Stored only in the macOS Keychain as a generic-password item keyed by
`kSecAttrAccount`, retrieved through `KeychainStore.shared.retrieve(key:)`.
Referenced by `ProviderConfig.keychainKey`. Never written to config,
`UserDefaults`, logs, error messages, the request URL, or the UI.

---

## Enumerations

### `ProviderKind` — no change

```swift
public enum ProviderKind: String, Codable, Equatable {
  case openAICompatible = "openai"
  case anthropic = "anthropic"   // already present — this feature makes it work
  case ollama = "ollama"
  case gemini = "gemini"
}
```

### `ProviderError` — no change

Unlike 004, which added `responseBlocked(reason:)` and `emptyResponse`, this
feature adds **no cases**. Every Anthropic outcome maps onto the existing set
(see `research.md` R6), so `Sources/Overtype/Providers/AIProvider.swift` is not
edited at all.

Cases used by this provider: `apiKeyMissing`, `invalidURL`, `networkError`,
`apiError(statusCode:message:)`, `invalidResponse`, `timeout`, `cancelled`,
`responseBlocked(reason:)`, `emptyResponse`.

`isRetryable` and `logLabel` are inherited unchanged, which is what makes FR-011
a zero-code requirement: 429 and 529 already classify as retryable, 4xx does not.

---

## Transient request/response mapping

In-memory only; nothing here is persisted.

| Source | Request field |
|---|---|
| resolved model (action, else provider default) | `model` |
| provider constant `8192` | `max_tokens` |
| action `systemPrompt` | `system` (top-level) |
| action `userPromptTemplate` with `{{text}}` → selection | `messages[0].content`, `role: "user"` |
| action `temperature` | **not sent** (FR-007) |
| — | no `thinking` / `effort` field sent (research R4) |

| Response element | Consumed as |
|---|---|
| `content[]` blocks where `type == "text"` | concatenated in order → returned text |
| `content[]` blocks of any other type (`thinking`, `redacted_thinking`, …) | **skipped** (FR-008) |
| `stop_reason` | success / blocked classification (research R6) |
| `stop_details.category` | refusal detail appended to the blocked reason |
| `stop_details.explanation` | **deliberately unused** — server prose that may echo submitted text |
| `usage`, `id`, `role`, `model` | ignored |

Full wire shapes: [`contracts/anthropic-messages.md`](./contracts/anthropic-messages.md).

---

## State transitions

None. A run is a single stateless request/response inside the existing
`ActionEngine` pipeline; the provider holds no state between calls beyond its
injected `ProviderConfig` and `URLSession`.
