# Phase 1 Data Model: Gemini Model Support

**Feature**: 004-gemini-provider | **Date**: 2026-08-02

This feature adds no new persisted schema. It adds one enum case and two error
values, and it reuses the existing `ProviderConfig` and `ActionConfig` records.
The entities below describe how existing structures are used for Gemini.

## Configuration entities (existing, reused)

### ProviderConfig (Gemini instance)

A Gemini provider is an ordinary `ProviderConfig` record with `kind == .gemini`.
No new fields are added to the struct.

| Field | Type | For Gemini |
|-------|------|-----------|
| `id` | String | User-chosen id (e.g. `"gemini"`), referenced by actions. |
| `kind` | `ProviderKind` | **`.gemini`** (new case, wire value `"gemini"`). |
| `baseURL` | `URL?` | Optional. If nil, provider defaults to `https://generativelanguage.googleapis.com/v1beta/`. |
| `defaultModel` | String | Recommended `"gemini-3.5-flash-lite"`. Used when the action sets no model. |
| `timeoutSeconds` | Double | Hard request timeout. Default 30. |
| `keychainKey` | `String?` | Keychain reference for the Gemini API key (e.g. `"gemini-api-key"`). |

**Validation / rules**:
- `keychainKey` must be present and resolve to a non-empty key, else the run
  fails with `ProviderError.apiKeyMissing` before any network call.
- `defaultModel` must be non-empty (struct requires it).
- Model resolution: `ActionConfig.model ?? ProviderConfig.defaultModel`
  (unchanged pipeline behavior).

### ActionConfig (existing, unchanged)

An action targets Gemini simply by setting `providerID` to the Gemini provider's
`id`. Optional `model` overrides the provider default. No structural change.

### Gemini API Key (secret, existing storage)

Stored only in the macOS Keychain, referenced by `keychainKey`. Never present in
`ProviderConfig`, `config.json`, `UserDefaults`, logs, error messages, or UI.

## Enumerations

### ProviderKind (edited)

```
openAICompatible = "openai"
anthropic        = "anthropic"
ollama           = "ollama"
gemini           = "gemini"   // NEW
```

### ProviderError (edited — two new cases)

```
apiKeyMissing
invalidURL
networkError(Error)
apiError(statusCode: Int, message: String)
invalidResponse
timeout
cancelled
contextChanged
responseBlocked(reason: String)   // NEW — safety/blocklist/prohibited/empty-candidates block
emptyResponse                     // NEW — completion succeeded but produced no usable text
```

New `errorDescription` values (human-readable, no secrets):
- `responseBlocked(reason:)` → e.g. "Gemini blocked the response (reason: SAFETY). Nothing was changed."
- `emptyResponse` → e.g. "Gemini returned no text to write. Nothing was changed."

## Transient request/response (in-memory only, not persisted)

These map the existing `TransformRequest` onto the Gemini wire schema inside
`GeminiProvider`. Full field-by-field contract is in
[`contracts/gemini-generatecontent.md`](./contracts/gemini-generatecontent.md).

- **Request** (built from `TransformRequest`): `systemInstruction.parts[].text`
  from `systemPrompt`; `contents[0].parts[0].text` from the rendered user prompt
  (`userPromptTemplate` with `{{text}}` → selected text);
  `generationConfig.temperature` from `temperature`.
- **Response** (parsed): success reads `candidates[0].content.parts[*].text`;
  failure inspects HTTP status, `promptFeedback.blockReason`,
  `candidates[0].finishReason`, and presence of text parts, per the mapping in
  `research.md` R6.

## State transitions

A single Gemini run is stateless request/response within the existing
`ActionEngine` sequence (read → call → sanitize → context re-check → write). No
new persistent state or lifecycle is introduced.
