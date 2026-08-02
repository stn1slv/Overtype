# Contract: Gemini `generateContent` (text)

**Feature**: 004-gemini-provider | **Source**: Google AI for Developers,
`https://ai.google.dev/api/generate-content` (retrieved 2026-08-02).

This is the external contract `GeminiProvider` depends on. It is the only network
endpoint the feature contacts.

## Request

- **Method**: `POST`
- **URL**: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
  - `{model}` = resolved model (action model, else provider `defaultModel`), e.g.
    `gemini-3.5-flash-lite`.
  - Base is overridable via `ProviderConfig.baseURL`; default is
    `https://generativelanguage.googleapis.com/v1beta/`.
- **Headers**:
  - `Content-Type: application/json`
  - `x-goog-api-key: <API key from Keychain>`  ← key is NEVER placed in the URL.
- **Body**:

```json
{
  "systemInstruction": {
    "parts": [{ "text": "<action.systemPrompt>" }]
  },
  "contents": [
    {
      "role": "user",
      "parts": [{ "text": "<userPromptTemplate with {{text}} replaced>" }]
    }
  ],
  "generationConfig": {
    "temperature": 0.2
  }
}
```

Notes:
- `maxOutputTokens` is intentionally omitted (no output limit exists in
  `ActionConfig`; parity with the OpenAI provider).
- `safetySettings` is omitted; Gemini default safety applies.

## Success response (HTTP 200)

```json
{
  "candidates": [
    {
      "content": { "parts": [{ "text": "<result text>" }], "role": "model" },
      "finishReason": "STOP",
      "safetyRatings": []
    }
  ],
  "usageMetadata": { "promptTokenCount": 10, "candidatesTokenCount": 100, "totalTokenCount": 110 }
}
```

- **Extract**: concatenate `candidates[0].content.parts[*].text`. Hand the result
  to `ResponseSanitizer`, then to the write stage.
- `finishReason` values: `STOP`, `MAX_TOKENS`, `SAFETY`, `OTHER`. `MAX_TOKENS`
  with non-empty text is treated as a normal (possibly truncated) success and
  sanitized like any other output.

## Failure responses

### Blocked (HTTP 200 but no usable content)

```json
{
  "promptFeedback": { "blockReason": "SAFETY", "safetyRatings": [] },
  "candidates": []
}
```

- `blockReason` values: `SAFETY`, `BLOCKLIST`, `PROHIBITED_CONTENT`,
  `IMAGE_SAFETY`, `OTHER`.
- Also treat as blocked: a candidate with `finishReason == "SAFETY"` or a
  candidate that carries no text part.
- **Map to**: `ProviderError.responseBlocked(reason:)` where `reason` is the
  `blockReason` or `finishReason` string.

### Completed but empty

- `candidates[0]` present, `finishReason` `STOP`/`MAX_TOKENS`, but no non-empty
  text after concatenation.
- **Map to**: `ProviderError.emptyResponse`.

### HTTP error (non-200)

```json
{ "error": { "code": 400, "message": "API key not valid...", "status": "INVALID_ARGUMENT" } }
```

- Common: `400` invalid key / bad request, `403` permission, `404` unknown model,
  `429` quota/rate limit, `5xx` server error.
- **Map to**: `ProviderError.apiError(statusCode:, message:)`, extracting
  `error.message` (fallback: truncated raw body). Network/timeout failures from
  `URLSession` map to `.networkError`/`.timeout`.

## Contract test intent (pure logic, unit-tested)

Given canned JSON bodies (fixtures in the test), the parsing/mapping logic MUST:
1. Return the concatenated text for a normal success body.
2. Concatenate multiple `parts[*].text` in order.
3. Throw `.responseBlocked` for a `promptFeedback.blockReason` body and for a
   `finishReason == "SAFETY"` candidate.
4. Throw `.emptyResponse` for a candidate with empty/absent text and a
   non-safety finish reason.
5. Throw `.apiError` with the extracted `error.message` for a non-200 body.
6. Throw `.invalidResponse` for a structurally unexpected body.

These exercise pure functions only; the live HTTP call is covered by manual
acceptance (see `quickstart.md`).
