# Contract: Generation Parameters in Provider Requests

Each provider exposes a pure static request-body builder. Unit tests assert the presence and absence of every key below (FR-025).

## OpenAI-compatible (`POST <baseURL>/chat/completions`)

| Input | Body |
|---|---|
| `temperature: Double?` | `"temperature": <value>` only when non-nil |
| `reasoning: .level(v)` | `"reasoning_effort": "<v>"` |
| `reasoning: .thinkingBudget` | not sent (the resolver never produces it for this kind) |
| `reasoning: nil` | no `reasoning_effort` key |

Always present: `model`, `messages` (system, user). No other keys are added.

Error classification on a non-200 response:
- HTTP 400 with `error.param` equal to `temperature`, and the sent temperature within 0.0 to 2.0 → `ProviderError.parameterRejected(.temperature, ...)`.
- HTTP 400 with `error.param` equal to `reasoning_effort`, and the sent level in the OpenAI value list (`none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`) → `ProviderError.parameterRejected(.reasoning, ...)`.
- Anything else, including a named parameter whose sent value is outside those ranges (a typo such as temperature 5 or effort `ultra`) → `ProviderError.apiError(statusCode:message:)`, unchanged, so the user sees the API error.

## Anthropic (`POST <base>messages`)

| Input | Body |
|---|---|
| temperature | never sent (feature 007; the builder takes no temperature argument) |
| `reasoning: .level(v)` | `"output_config": {"effort": "<v>"}` |
| `reasoning: nil` | no `output_config` key |

Always present: `model`, `max_tokens` (8192), `system`, `messages`. No `thinking` key.

## Gemini (`POST <base>models/<model>:generateContent`)

| Input | `generationConfig` |
|---|---|
| `temperature: Double?` | `"temperature": <value>` only when non-nil |
| `reasoning: .level(v)` | `"thinkingConfig": {"thinkingLevel": "<v>"}` |
| `reasoning: .thinkingBudget(n)` | `"thinkingConfig": {"thinkingBudget": n}` |
| both nil | `generationConfig` omitted entirely |

`thinkingLevel` and `thinkingBudget` never appear together. Always present: `systemInstruction`, `contents`.

## Ollama (`POST <base>/api/chat`)

| Input | `options` |
|---|---|
| `temperature: Double?` | `"temperature": <value>` only when non-nil |
| reasoning | never sent (`think` stays omitted, feature 008) |

`options.num_ctx` is always present, so `options` is never empty. Top-level keys unchanged: `model`, `messages`, `stream`, `options`.

## Adaptive fallback (engine, `ActionEngine.transformWithRetry`)

1. A `parameterRejected(p, ...)` error whose parameter `p` is in the current request and was not dropped yet in this run: check cancellation, record `p` with the value the run sent in `ParameterRejectionMemory`, log `p`, provider id and model at `warning` (never the message), show "Retrying...", and resend without `p`. No retry pause. Later runs withhold `p` only while they would send that same value; a changed value is sent again.
2. A `parameterRejected` that cannot be dropped: rethrown as `apiError(statusCode:message:)`.
3. The existing transient retry (`isRetryable`, one retry, configured pause) is unchanged and independent.
4. Upper bound per run: one drop per `DroppableParameter` (two) plus one transient retry, so at most four requests.
5. Only the OpenAI-compatible provider throws `parameterRejected`, so the fallback never fires for other kinds (FR-015).
