# Research: Model-Aware Generation Parameters

All provider facts below were read on 2026-10-17 from the vendors' own `llms.txt` indexes and the pages they link. Each profile in `contracts/model-profiles.md` cites the entry here that it is based on. Facts marked **inferred** are not stated by the vendor and are confirmed only by the acceptance run named next to them.

## R1. OpenAI GPT-6 family

**Sources**: `developers.openai.com/api/docs/guides/latest-model/gpt-6-astra.md` (Using GPT-6), `.../guides/reasoning.md`, model pages `.../models/gpt-6-luna.md`, `gpt-6-sol.md`, `gpt-6-astra.md`, `gpt-6.1-sol.md`.

| Model | `reasoning_effort` values | Default | Temperature |
|---|---|---|---|
| `gpt-6-luna` | none, low, medium, high, xhigh, max | medium | only at `none` (**inferred**) |
| `gpt-6-sol` | none, low, medium, high, xhigh, max | medium | only at `none` (**inferred**) |
| `gpt-6-astra` | low, medium, high, xhigh, max | medium | never |
| `gpt-6.1-sol` | low, medium, high, xhigh, max | medium | never |

- The guide states: "When reasoning effort is not `none`, remove `temperature`, `top_p`, and `top_logprobs`." It does not state that temperature is accepted at `none`; that is the inference. SC-001 confirms it for `gpt-6-luna`.
- **Verified 2026-10-17 (quickstart Q1):** `gpt-6-luna` with effort `none` and temperature 0 returned HTTP 200, confirming the inference. Every 400 named the rejected parameter in `error.param` (code `unsupported_value`), which R2 relies on. The table above lists `max` from the model pages, but Chat Completions rejects it for all four models; the error lists `none`, `low`, `medium`, `high`, `xhigh` for Luna and Sol and `low`, `medium`, `high`, `xhigh` for Astra and 6.1 Sol. The profiles use the verified lists.
- Chat Completions supports all four models for requests without tools, which is all Overtype sends.
- No dated snapshots are documented yet; each page names the plain ID as the default snapshot.

**Decision**: Profiles for these four IDs. Preferred effort: `none` for Luna and Sol, `low` for Astra and 6.1 Sol (lowest supported).
**Rationale**: Overtype rewrites text while the user waits; the lowest effort is the fastest.
**Alternatives considered**: Leaving effort at the model default (`medium`): rejected, it is the slowest acceptable choice and is the behavior that produced the reported 400 together with the stored temperature.

## R2. OpenAI error format for a rejected parameter

**Source**: `.../guides/error-codes.md` documents `error.param` (example: `service_tier`, type `invalid_request_error`). The temperature rejection from the user's screenshot is a 400 with message "Unsupported value: 'temperature' does not support 0 with this model".

**Decision**: The fallback reads `error.param` only. Values `temperature` and `reasoning_effort` are droppable; any other value, or no `param`, keeps today's error.
**Rationale**: FR-016 forbids matching message text. If the diagnostic run (FR-014, quickstart Q1) shows that `param` is absent for these errors, the fallback stays inert rather than wrong, and the profiles still fix every profiled model.
**Alternatives considered**: Parsing the message text: rejected by FR-016 (fragile, and the message can echo user content).

## R3. Anthropic effort and sampling

**Sources**: `platform.claude.com/docs/en/build-with-claude/effort.md`, `.../build-with-claude/thinking.md` (Sampling parameters), `.../api/models/retrieve.md`, `.../api/errors.md`, `.../about-claude/model-deprecations.md`.

- Effort is `output_config.effort`, no beta header. Values `low`, `medium`, `high`, `xhigh`, `max`; there is no `none` or `minimal`. Defaults: `high`, except `medium` on Opus 5.5 and Haiku 5.5.
- `supportedModels`: claude-fable-5-1, claude-mythos-5-1, claude-fable-5, claude-mythos-5, claude-mythos-preview, claude-opus-5-5, claude-opus-5, claude-opus-4-8, claude-opus-4-7, claude-opus-4-6, claude-opus-4-5-20251101, claude-sonnet-5-5, claude-sonnet-5, claude-sonnet-4-6, claude-haiku-5-5.
- `max`: all of the above except Opus 4.5. `xhigh`: all except Opus 4.6, Opus 4.5, Sonnet 4.6 and Mythos Preview.
- Sampling: the twelve newest models reject any non-default `temperature`, `top_p` or `top_k` with 400 on every request; older models reject `temperature` only while thinking is on.
- Error body is `{"type":"error","error":{"type","message"},"request_id"}`: no parameter field.
- `claude-haiku-4-5-20251001`: active, tentative retirement "not sooner than October 15, 2026" (that window is open). `claude-sonnet-4-5-20250929`: deprecated. `claude-mythos-preview`: deprecated, no date.

**Decision**: Profiles for the fifteen IDs, preferred `low`. No profile for Haiku 4.5 or Sonnet 4.5 (no effort support, so a profile would change nothing). Temperature stays omitted for every Anthropic request (spec Clarifications). The README Anthropic recipe moves from `claude-haiku-4-5` to `claude-haiku-5-5` (FR-027), and its two notes that cite Haiku 4.5 as accepting temperature are rewritten.
**Rationale**: `low` is the lowest effort every listed model supports.
**Alternatives considered**: Turning thinking off instead (`thinking: {type: "disabled"}`): rejected, the accepted values differ per model and per effort (Sonnet 5.5 rejects it; Opus 5 and Haiku 5.5 reject it above `high`), so it adds a second per-model rule for a gain effort already gives.

## R4. Gemini thinking and sampling

**Sources**: `ai.google.dev/gemini-api/docs/generate-content/thinking.md.txt`, `.../docs/latest-model.md.txt`, `.../docs/generate-content/whats-new-gemini-3.5.md.txt`, `.../docs/generate-content/gemini-3.md.txt`, `.../docs/models.md.txt` and model pages, `ai.google.dev/api/models.md.txt`, `.../docs/troubleshooting.md.txt`.

| Model | Parameter | Values | Preferred | Temperature |
|---|---|---|---|---|
| `gemini-4-argon` | thinkingLevel | low, medium, high | low | omit |
| `gemini-3.8-flash` | thinkingLevel | low, medium, high | low | omit |
| `gemini-3.7-flash` (deprecated, routed to 3.8 Flash) | thinkingLevel | low, medium, high | low | omit |
| `gemini-3.6-flash` | thinkingLevel | minimal, low, medium, high | minimal | omit |
| `gemini-3.5-flash` (deprecated, routed to 3.6 Flash) | thinkingLevel | minimal, low, medium, high | minimal | omit |
| `gemini-3.5-flash-lite` | thinkingLevel | minimal, low, medium, high | minimal | omit |
| `gemini-3.1-flash-lite` | thinkingLevel | minimal, low, medium, high | minimal | omit |
| `gemini-3-flash-preview` | thinkingLevel | minimal, low, medium, high | minimal | omit |
| `gemini-3.1-pro-preview` | none recorded | | | omit |
| `gemini-2.5-pro` | thinkingBudget | 128 to 32768 (cannot disable) | 128 | accept |
| `gemini-2.5-flash` | thinkingBudget | 0 to 24576 | 0 | accept |

- `minimal` returns an error on Gemini 3.8 Flash and Gemini 4 Argon.
- Gemini 3.x: "Remove these parameters from all requests" (temperature, top_p, top_k); setting temperature below 1.0 "may" cause looping or degraded performance. Gemini 4: "If provided, they are ignored."
- Gemini 2.5 does not support `thinkingLevel`; Gemini 4 deprecates `thinkingBudget`; "sending `thinkingBudget` and `thinkingLevel` together returns a `400` error".
- `gemini-2.5-flash-lite` does not think by default and gets no profile (a profile would change nothing). `gemini-3.1-pro-preview` gets a profile only for its temperature rule, because its thinking levels are not in the table.
- `models.get` returns `thinking` (bool), `temperature`, `maxTemperature`, `topP`, `topK`; no per-level support. The troubleshooting page documents no field naming a rejected parameter.
- `gemini-3.5-flash-lite` is listed as Stable, so the README Gemini recipe stands.

**Decision**: Profiles as in the table. A resolver output holds at most one Gemini thinking parameter.
**Rationale**: The lowest supported level is the fastest; the budget values follow the same rule for 2.5.
**Alternatives considered**: Runtime `models.get` lookup: rejected by the user (spec Clarifications).

## R5. Snapshot matching

**Decision**: A model ID matches a profile when it equals the profile ID, or equals the profile ID followed by `-YYYY-MM-DD` or `-YYYYMMDD` (all digits, plausible date). Gemini preview IDs are listed explicitly in the table, never matched by rule.
**Rationale**: A loose prefix rule would make `gpt-6-luna` match a future `gpt-6-luna-mini`, and Gemini uses `-preview` as part of real stable IDs.
**Alternatives considered**: Prefix matching: rejected for the reason above.

## R6. Where the adaptive fallback lives

**Decision**: In `ActionEngine.transformWithRetry`, the existing tested seam. `OpenAICompatibleProvider` only classifies: on a 400 whose `error.param` is droppable it throws the new `ProviderError.parameterRejected(_:statusCode:message:)`; otherwise it throws `apiError` exactly as today. The engine drops the parameter, records it, shows "Retrying...", and repeats without the retry pause (a rejection is not a rate limit). At most one drop per parameter plus the existing single transient retry: never more than four requests per run. A rejection that cannot be dropped (parameter not in the request, or already dropped) is rethrown as `apiError(statusCode:message:)` so the existing HUD text and debug-only log path apply.
**Rationale**: Keeps providers free of retry policy, keeps the bound testable with a fake provider, and leaves the user-facing error unchanged when no drop is possible.
**Alternatives considered**: Retrying inside the provider: rejected, it cannot show HUD progress and would hide a second retry policy from `TransformRetryTests`.

## R7. Learned-rejection store

**Decision**: An in-memory, lock-protected store keyed by `(providerID, baseURL.absoluteString, model)`, holding a set of droppable parameters. Cleared only by quitting the app.
**Rationale**: Runs execute in a `Task`; a lock keeps reads and writes safe. The OpenAI provider requires a base URL, so the key is always complete. A changed model or base URL gets a fresh key (FR-012).
**Alternatives considered**: Persisting to disk: rejected in the spec (a wrong rule would persist).

## R8. Principle IV and new code

**Decision**: New code keys all per-kind data (profiles, editor value lists, the suggested default model) by `ProviderKind` in dictionaries, where absence means "none". No new exhaustive `switch` over `ProviderKind`.
**Rationale**: Adding a provider must stay a three-edit change; an exhaustive switch in new code would force a fourth edit.

## R9. Gemini request body when nothing is configured

**Decision**: `generationConfig` is omitted entirely when it would be empty, and `thinkingConfig` is omitted when no thinking parameter is set.
**Rationale**: An empty object adds nothing and is one more thing a server could reject; the unit test asserts absence.
