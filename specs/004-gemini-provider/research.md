# Phase 0 Research: Gemini Model Support

**Feature**: 004-gemini-provider | **Date**: 2026-08-02

This resolves the technical unknowns for a native Gemini provider. All items in
the plan's Technical Context are decided; none remain marked NEEDS CLARIFICATION.

## R1. Integration approach: native provider vs. OpenAI-compatible shim

- **Decision**: Build a dedicated native `GeminiProvider` that calls the Gemini
  `generateContent` REST API. (Locked by the 2026-08-02 clarification session.)
- **Rationale**: The native API returns `finishReason` and
  `promptFeedback.blockReason`, letting us map safety blocks and empty responses
  to specific typed errors (FR-006). It also matches the constitution's
  extension model (Principle IV: new kind + new type + one factory line).
- **Alternatives considered**:
  - *Reuse `OpenAICompatibleProvider` against Google's OpenAI-compatible endpoint
    (`/v1beta/openai/chat/completions`)*: works for the happy path with zero new
    code, but Gemini-specific failures arrive through a compatibility shim as
    generic OpenAI-style errors, weakening FR-006. Rejected during clarification.

## R2. Endpoint, method, and model targeting

- **Decision**: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`.
  The provider uses `ProviderConfig.baseURL` if the user set one, otherwise
  defaults to `https://generativelanguage.googleapis.com/v1beta/`, and appends
  `models/{model}:generateContent`. `{model}` is the resolved model
  (action-level model, else provider `defaultModel`).
- **Rationale**: Matches Google's published REST reference. Putting the model in
  the path is the native convention (unlike OpenAI, which puts it in the body).
- **Alternatives considered**: `:streamGenerateContent` (streaming) — rejected,
  out of scope; the run is single-shot with a HUD, not incremental output.

## R3. Authentication

- **Decision**: Send the API key in the `x-goog-api-key` request header. Read it
  from the Keychain via `KeychainStore` using the provider's `keychainKey`.
- **Rationale**: Google supports the key either as a `?key=` query parameter or
  the `x-goog-api-key` header. The header form keeps the secret out of the URL,
  which protects against the key leaking into any URL-based logging or error
  string (Principle V). If the key is missing/empty, throw
  `ProviderError.apiKeyMissing` before any request, exactly like the OpenAI
  provider.
- **Alternatives considered**: `?key=` query parameter — rejected; a secret in
  the URL is easy to leak and violates the spirit of Principle V.

## R4. Request body mapping

- **Decision**: Map `TransformRequest` to:
  ```json
  {
    "systemInstruction": { "parts": [{ "text": "<systemPrompt>" }] },
    "contents": [{ "role": "user", "parts": [{ "text": "<rendered userPrompt>" }] }],
    "generationConfig": { "temperature": <temperature> }
  }
  ```
  The user prompt is the action's `userPromptTemplate` with `{{text}}` replaced
  by the selected text, identical to `OpenAICompatibleProvider`.
- **Rationale**: Minimal faithful mapping of the existing request shape onto the
  Gemini schema. `maxOutputTokens` is intentionally omitted: `ActionConfig`
  has no output-token limit today, and the OpenAI provider likewise sets no
  `max_tokens`. Keeping parity avoids introducing a new config field.
- **Alternatives considered**: Sending `safetySettings` to relax filtering —
  rejected; not requested, and loosening safety defaults is a decision the user
  did not ask for. Default safety behavior is used.

## R5. Response parsing and success path

- **Decision**: Read `candidates[0].content.parts[*].text`, concatenating the
  `text` of all parts in the first candidate, then hand the string to the
  existing `ResponseSanitizer` before the pipeline writes it.
- **Rationale**: A normal completion returns one candidate whose parts hold the
  text. Concatenating parts is safe even when the model splits output.
- **Alternatives considered**: Reading only `parts[0].text` — rejected; can drop
  content when the response is chunked into multiple parts.

## R6. Failure mapping (FR-006)

Map Gemini outcomes to typed `ProviderError` values so nothing fails silently:

| Gemini outcome | Detection | `ProviderError` |
|----------------|-----------|-----------------|
| Missing/empty key | key absent in Keychain | `.apiKeyMissing` |
| Invalid key / unknown model / bad request | HTTP 400/403 with `error.message` | `.apiError(statusCode, message)` |
| Quota / rate limit | HTTP 429 | `.apiError(statusCode, message)` |
| Server error | HTTP 5xx | `.apiError(statusCode, message)` |
| Network failure | `URLSession` throws | `.networkError(error)` |
| Timeout | `URLSession` timeout | `.timeout` (mapped from URLError) |
| Prompt blocked | `promptFeedback.blockReason` set, or empty `candidates` | `.responseBlocked(reason:)` **(new)** |
| Candidate blocked / no text | `finishReason == "SAFETY"` or no text parts | `.responseBlocked(reason:)` **(new)** |
| Empty but not blocked | candidate present, text empty, `finishReason` STOP/MAX_TOKENS | `.emptyResponse` **(new)** |
| Unparseable body | JSON shape unexpected | `.invalidResponse` (existing) |

- **Decision**: Add two `ProviderError` cases: `responseBlocked(reason: String)`
  and `emptyResponse`, each with a specific human-readable `errorDescription`.
  Reuse `.apiError` for HTTP-status failures, extracting `error.message` from the
  Gemini error body (same `{ "error": { "message": ... } }` shape the OpenAI
  provider already parses, so `extractErrorMessage` logic is reusable).
- **Rationale**: FR-006 requires distinguishing credentials, unknown model,
  quota, network, and empty/blocked responses. HTTP-status failures already carry
  the server message; only the block/empty cases need new typed values.
- **Alternatives considered**: Folding blocked/empty into `.invalidResponse` —
  rejected; that message ("invalid response") misleads the user about a safety
  block and violates the "specific, human-readable error" requirement.

## R7. Error body shape

- **Decision**: On non-200, parse `{ "error": { "code", "message", "status" } }`
  and surface `message` through `.apiError`. Fall back to a truncated raw body
  when absent (same fallback the OpenAI provider uses).
- **Rationale**: Gemini's REST error body matches this shape; reusing the
  existing extraction keeps behavior consistent across providers.

## R8. Timeout, cancellation, and logging

- **Decision**: Reuse the ephemeral `URLSession` timeout pattern from
  `OpenAICompatibleProvider` (`timeoutIntervalForRequest/Resource =
  config.timeoutSeconds`). Cancellation flows through the existing Escape monitor
  and Swift structured concurrency. The request URL, headers, body, and response
  text are never logged at `info`; any diagnostic uses `sanitizedLog()` at debug.
- **Rationale**: Consistency with the existing provider and Principles V and VI.

## Open questions

None. All Technical Context items are resolved.

## Source

Gemini `generateContent` REST reference, Google AI for Developers
(`https://ai.google.dev/api/generate-content`), retrieved 2026-08-02. Captured in
`contracts/gemini-generatecontent.md`.
