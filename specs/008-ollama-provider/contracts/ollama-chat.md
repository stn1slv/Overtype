# Contract: Ollama Chat API (`POST /api/chat`)

**Feature**: `008-ollama-provider` | **Source**: Ollama published API reference
(`docs.ollama.com/api/chat`, `/api/streaming`), client version observed locally
`0.32.5`.

This is the exact subset of the wire format Overtype relies on. Fields Ollama
supports but Overtype never sends or never reads are listed at the end so that a
future reader can see the omissions are deliberate.

---

## Endpoint

```
POST {base}/api/chat
Content-Type: application/json
Authorization: Bearer <credential>      # ONLY when the user stored one (R8)
```

`{base}` is `ProviderConfig.baseURL` if set, otherwise `http://localhost:11434`.
A trailing slash on the configured value is normalised before `api/chat` is
appended, mirroring `AnthropicProvider.endpointURL(base:)`.

## Request body

```json
{
  "model": "llama3.2",
  "messages": [
    { "role": "system", "content": "You are a grammar corrector..." },
    { "role": "user",   "content": "Fix the grammar: The cat are sleeping." }
  ],
  "stream": false,
  "options": {
    "temperature": 0.0,
    "num_ctx": 16384
  }
}
```

| Field | Required | Source | Notes |
|---|---|---|---|
| `model` | yes | action `model`, else provider `defaultModel` | Never hard-coded |
| `messages[0]` | yes | `action.systemPrompt` | Sent as `role: "system"`; unlike Anthropic there is no top-level `system` field |
| `messages[1]` | yes | `action.userPromptTemplate` with `{{text}}` replaced by the selection | Same templating as the other providers |
| `stream` | yes, as `false` | fixed | Defaults to `true`. Streaming returns newline-delimited JSON, which would break single-document parsing and could write a partial answer (FR-010) |
| `options.temperature` | no | `action.temperature` | Sent, unlike Anthropic (R4) |
| `options.num_ctx` | no | fixed `16384` | Prevents silent prompt truncation (FR-010a, R3) |

## Success response (HTTP 200)

```json
{
  "model": "llama3.2",
  "created_at": "2026-08-06T10:00:00.000000Z",
  "message": {
    "role": "assistant",
    "content": "The cat is sleeping.",
    "thinking": "The subject is singular, so..."
  },
  "done": true,
  "done_reason": "stop",
  "total_duration": 1234567890,
  "load_duration": 987654321,
  "eval_count": 7
}
```

Overtype reads two fields: `message.content` for the answer, and
`prompt_eval_count` to verify the prompt was not clipped.

- `message.thinking` is **never read**. It carries model reasoning and must not
  reach the user's document (FR-009 layer 1). This is an allow-list, not a
  deny-list: any future sibling field is ignored by default.
- `done_reason` is **not** treated as a failure signal. Unlike Anthropic's
  `stop_reason`, Ollama has no refusal category here; a non-empty answer is a
  success regardless. An empty or whitespace-only `content` (after layer 2)
  becomes `.emptyResponse`.
- `prompt_eval_count` is compared against the same prompt budget as the
  pre-send check. A count above it means the prompt was truncated, and the
  answer is refused with `inputTooLargeForContext` rather than written. This is
  a backstop; the pre-send check is the primary guard. Other timing and
  token-count fields are ignored.
- A body that is not an object, or has no `message.content` string, is
  `.invalidResponse`.

### Reasoning inside `content` (FR-009 layer 2)

Some models emit reasoning inside `content` instead of using `thinking`:

```json
{ "message": { "role": "assistant",
               "content": "<think>The subject is singular.</think>The cat is sleeping." } }
```

Contract for `stripLeadingReasoningBlock(_:)`:

| Input (trimmed `content`) | Result |
|---|---|
| `<think>reasoning</think>answer` | `answer` |
| `<thinking>reasoning</thinking>answer` | `answer` |
| `answer` (no marker) | `answer`, unchanged |
| `answer containing <think> mid-text` | unchanged — only a block at the **start** is removed |
| `<think>reasoning` (no closing marker) | empty → provider throws `.emptyResponse` |
| `<think></think>` | empty → provider throws `.emptyResponse` |
| `<think>a</think><think>b</think>answer` | `answer` — consecutive leading blocks are all removed |
| `<thinking>x</think>y` | empty → mismatched markers fail safe as `.emptyResponse` |

Marker matching is case-insensitive on the tag name. The result is trimmed of
leading whitespace and newlines before the empty check.

## Pre-send refusal (FR-010b)

Before a request is built, the provider estimates the tokens in the composed
prompt (system prompt plus the rendered user prompt, `utf8.count` each — see
research R13 for why bytes and not characters) and throws
`inputTooLargeForContext(limit:)` if the total exceeds the budget, which is
`min(6000, grantedWindow / 2)`. Nothing is sent, so this is not a wire condition — it is listed
here because it is part of the provider's observable contract.

| Estimated prompt tokens | Result |
|---|---|
| ≤ budget | Request is built and sent |
| > budget | `inputTooLargeForContext(limit: budget)`, no request, selection unchanged, no retry |

The budget is `min(6000, grantedWindow / 2)`: measured against a 2048-window
model, the server keeps only ~1026 prompt tokens (half the window) and answers
from that, silently.

## Failure responses

| HTTP | Body | Mapped to |
|---|---|---|
| — (transport) | `URLError.cannotConnectToHost` / `.cannotFindHost` | `serviceUnreachable(address:)` — carries the endpoint host **and port**, non-retryable |
| — (transport) | `URLError.networkConnectionLost` | `.networkError` (existing, retryable). Deliberately NOT `serviceUnreachable`: the connection was established and then dropped, which proves the service was reachable |
| — (transport) | `URLError.timedOut` | `.timeout` (existing, retryable) |
| — (transport) | `URLError.cancelled` / `CancellationError` | `.cancelled` (existing) |
| 404 | `{"error":"model 'llama3.2' not found"}` (the wording varies by version; 0.32.5 omits the documented "try pulling it first" suffix) — **must be Ollama's own JSON `{"error": String}` shape**, so an HTML 404 page from a proxy is not misread | `modelNotAvailable(model:)` — carries the **requested** model name from the request, never a parsed fragment of the server string, non-retryable |
| 400 | `{"error":"invalid options: ..."}` | `apiError(statusCode:message:)` |
| 403 | `{"error":"..."}` | `apiError(statusCode:message:)` (reachable when the service restricts origins) |
| 5xx | `{"error":"..."}` | `apiError(statusCode:message:)` — retryable via the existing shared rule |

Error body shape is `{"error": "<string>"}` — a **string**, unlike OpenAI's
`{"error": {"message": "<string>"}}`. `OllamaProvider.extractErrorMessage(from:)`
handles the string shape first and delegates to
`OpenAICompatibleProvider.extractErrorMessage(from:)` otherwise, which itself
falls back to a 200-character truncation of the raw body.

## Deliberate omissions

Not sent, each for a recorded reason:

| Field | Why not |
|---|---|
| `think` | Models that do not support it reject the whole request; feature 007 already rejected this per-model allow-list pattern (clarification 2) |
| `keep_alive` | Memory-residency policy stays with the service and its own settings (clarification 7, FR-011) |
| `tools`, `format` | Out of scope: text-in / text-out only |
| `logprobs`, `top_logprobs` | Not used |
| `options.num_predict` | No output cap is imposed; the model's own default applies, matching `GeminiProvider`, which also sends no output cap |

Not read: `message.thinking`, `message.tool_calls`, `message.images`,
`done_reason`, and all timing/token fields except `prompt_eval_count`.

## Companion endpoint: `POST {base}/api/show`

Sends `{"model": "<name>"}` and reads `model_info.<arch>.context_length` (matched
by suffix, since the key is architecture-prefixed). Used once per model, cached,
to learn the window the service will actually grant — Ollama clamps `num_ctx`
down to a model's own maximum, so the requested value is not a safe basis for
the truncation check. Carries no user text. A failure is non-fatal: the check
falls back to the requested window.
