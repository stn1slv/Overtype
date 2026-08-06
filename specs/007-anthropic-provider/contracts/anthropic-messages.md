# Contract: Anthropic Messages API (`POST /v1/messages`)

**Feature**: `007-anthropic-provider` | **Date**: 2026-08-06

The external wire contract this provider depends on. Source and retrieval date
are recorded at the end of [`../research.md`](../research.md).

---

## Request

**Method / URL**

```text
POST <base>messages
```

`<base>` defaults to `https://api.anthropic.com/v1/` and is overridden by
`ProviderConfig.baseURL` when set. The base is normalised to end in `/` before
`messages` is appended.

**Unlike Gemini, the model name is not in the path.** There is one fixed path, so
no percent-encoding workaround is needed.

**Headers**

```text
Content-Type: application/json
x-api-key: <API key from Keychain>        ← key is NEVER placed in the URL
anthropic-version: 2023-06-01             ← required; request is rejected without it
```

**Body**

```json
{
  "model": "claude-haiku-4-5",
  "max_tokens": 8192,
  "system": "<action systemPrompt>",
  "messages": [
    { "role": "user", "content": "<userPromptTemplate with {{text}} substituted>" }
  ]
}
```

**Notes on the body**

- `max_tokens` is **required**. It caps reasoning *plus* answer text together.
- `system` is a **top-level field**. A `{"role": "system"}` entry inside
  `messages` is a validation error.
- `temperature` / `top_p` / `top_k` are **deliberately omitted**. Current Claude
  models reject them with HTTP 400 (spec Clarifications, research R4).
- No `thinking` or `effort` field is sent — accepted values differ per model
  (research R4).
- No `tools`, no `stream`. This provider is non-streaming and tool-free.

---

## Success response (HTTP 200)

```json
{
  "id": "msg_01…",
  "type": "message",
  "role": "assistant",
  "model": "claude-haiku-4-5",
  "content": [
    { "type": "text", "text": "The corrected sentence." }
  ],
  "stop_reason": "end_turn",
  "stop_details": null,
  "usage": { "input_tokens": 42, "output_tokens": 17 }
}
```

**Extraction rule**: concatenate, in order, the `text` of every block whose
`type` is exactly `"text"`. Skip every other block type. Never index
`content[0]` — a reasoning block may legitimately come first.

**A response carrying reasoning** looks like this, and only the second block may
be written:

```json
"content": [
  { "type": "thinking", "thinking": "The user wants…", "signature": "…" },
  { "type": "text",     "text": "The corrected sentence." }
]
```

**`stop_reason` values**

| Value | Treatment |
|---|---|
| `end_turn` | Normal completion → success |
| `max_tokens` | Length-truncated → **success if text is non-empty**, else `.emptyResponse` |
| `stop_sequence` | Normal completion → success |
| `refusal` | → `.responseBlocked` |
| `tool_use`, `pause_turn` | Unreachable here (no tools sent); → `.responseBlocked` if seen |
| absent / `null` | Falls through to text extraction; not treated as a block |

**`stop_details`** is populated only on `stop_reason: "refusal"`:

```json
"stop_details": { "type": "refusal", "category": "cyber", "explanation": "…" }
```

`category` is used to enrich the blocked reason. `explanation` is **never used** —
it is server-authored prose that may echo submitted text, and the reason string
reaches a user-visible message.

---

## Failure responses

### Model declined (HTTP 200)

`stop_reason == "refusal"`. **Map to**: `.responseBlocked(reason:)` — using
`stop_details.category` when present (e.g. `refusal (cyber)`), otherwise
`refusal`.

### Completed but empty (HTTP 200)

No `text` block, or all `text` blocks empty after filtering.
**Map to**: `.emptyResponse`.

### Unparseable (HTTP 200)

Body is not JSON, or `content` is missing / not an array.
**Map to**: `.invalidResponse`.

### HTTP error (non-200)

```json
{
  "type": "error",
  "error": { "type": "rate_limit_error", "message": "Number of requests has exceeded…" }
}
```

**Map to**: `.apiError(statusCode:message:)`, with the message extracted by the
existing shared `OpenAICompatibleProvider.extractErrorMessage(from:)` (it already
reads `error.message`).

| Status | `error.type` | Retryable via existing `isRetryable` |
|---|---|---|
| 400 | `invalid_request_error` | No |
| 401 | `authentication_error` | No |
| 403 | `permission_error` | No |
| 404 | `not_found_error` (unknown model) | No |
| 413 | `request_too_large` | No |
| 429 | `rate_limit_error` | **Yes** |
| 500 | `api_error` | **Yes** |
| 529 | `overloaded_error` | **Yes** (falls in `500...599`) |

No code is written for the retry column — `ProviderError.isRetryable` already
classifies these correctly.

---

## Contract test intent (pure logic, unit-tested)

The parser MUST:

1. Return the concatenated text of all `type == "text"` blocks, in order.
2. **Skip `thinking` and `redacted_thinking` blocks**, and skip any unrecognised
   block type, returning only answer text.
3. Treat `stop_reason == "max_tokens"` with non-empty text as a success.
4. Throw `.responseBlocked` on `stop_reason == "refusal"`, incorporating
   `stop_details.category` when present.
5. Throw `.responseBlocked` on any other non-normal `stop_reason`.
6. Throw `.emptyResponse` when no text survives filtering.
7. Throw `.invalidResponse` on a non-JSON or structurally invalid body.

The endpoint builder MUST produce `https://api.anthropic.com/v1/messages` by
default and honour a `baseURL` override with or without a trailing slash.

The live HTTP call itself is **not** unit-tested. It is covered by the manual
acceptance procedure in [`../quickstart.md`](../quickstart.md), recorded in
`docs/compatibility.md` (Principle VIII).
