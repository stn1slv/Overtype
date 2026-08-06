# Phase 0 Research: Anthropic Claude Model Support

**Feature**: `007-anthropic-provider` | **Date**: 2026-08-06

All Technical Context unknowns are resolved below. Each decision records what was
chosen, why, and what was rejected.

---

## R1: Native Messages API vs. the OpenAI-compatible shim

**Decision**: A dedicated native provider (`AnthropicProvider`) calling
Anthropic's own Messages API, not `OpenAICompatibleProvider` pointed at a
compatibility endpoint.

**Rationale**: Identical to the reasoning in 004 (R1). The native wire format
exposes outcomes that a compatibility shim flattens or drops: a `refusal` stop
reason, and typed content blocks that separate answer text from model reasoning.
Both must map to specific typed errors (FR-010) or be filtered (FR-008). A shim
would surface a refusal as an ordinary empty completion, producing exactly the
silent no-op Principle VI forbids. The spec's Clarifications also settled that
this provider must omit `temperature`, which a generic OpenAI body builder always
sends.

**Alternatives considered**:
- *Reuse `OpenAICompatibleProvider` against a compatibility endpoint*: rejected —
  loses refusal detection and reasoning-block separation, and cannot express the
  temperature omission without special-casing the shared provider.
- *Extend `OpenAICompatibleProvider` with a kind switch*: rejected — puts
  vendor branching inside a provider that is currently vendor-neutral, and
  violates the Principle IV extension model (a new backend is a new type).

---

## R2: Endpoint, method, and where the model name goes

**Decision**: `POST <base>messages`, default base
`https://api.anthropic.com/v1/`. The model name travels **in the JSON body**, not
in the URL path.

**Rationale**: This is the one structural place Anthropic differs from Gemini and
it makes this provider *simpler* than its template. `GeminiProvider.endpointURL`
has to interpolate the model into the path and build the URL by string
concatenation specifically so the `:generateContent` action suffix is not
percent-encoded. Anthropic has a single fixed path, so `endpointURL` takes no
model argument and needs no colon-escaping workaround.

`baseURL` from `ProviderConfig` overrides the default when set, preserving the
existing escape hatch for proxies. The same trailing-slash normalisation as
Gemini is applied so a user-supplied base with or without a trailing slash works.

**Alternatives considered**:
- *Hardcode the absolute URL and ignore `baseURL`*: rejected — `ProviderConfig`
  already carries `baseURL` and users proxy provider traffic; silently ignoring a
  set field is a surprise.
- *Keep the model in the path for symmetry with Gemini*: not applicable — the
  API does not accept it there.

---

## R3: Authentication and the version header

**Decision**: Two headers on every request:
`x-api-key: <key from Keychain>` and `anthropic-version: 2023-06-01`.
The key is never placed in the URL.

**Rationale**: Principle V. A key in a query string leaks into any URL that gets
logged, which is the exact leak `GeminiProvider` avoids by using
`x-goog-api-key` rather than Google's documented `?key=` form. Anthropic's own
documented form is already a header, so there is nothing to avoid — but the same
constraint is restated here so it is not "simplified" later.

`anthropic-version` is **required** by the API; a request without it is rejected.
It is pinned to the literal `2023-06-01` as a provider constant. This is a
version identifier for the wire format, not a model version, and it has been
stable since introduction — pinning it is what the vendor intends, and it means a
future server-side default change cannot silently alter our request semantics.

**Alternatives considered**:
- *Make `anthropic-version` configurable*: rejected — no user need, and it would
  add a schema field (the same reason the response-length limit stays a constant,
  per Clarifications).
- *Omit `anthropic-version` and take the server default*: rejected — the API
  rejects the request outright.

---

## R4: Request body mapping

**Decision**:

```json
{
  "model": "<resolved model>",
  "max_tokens": 8192,
  "system": "<action systemPrompt>",
  "messages": [
    { "role": "user", "content": "<userPromptTemplate with {{text}} substituted>" }
  ]
}
```

**Rationale**:
- `system` is a **top-level field**, not a message with `role: "system"`. This
  differs from OpenAI and matches Gemini's `systemInstruction` split. Putting the
  system prompt in the `messages` array is a validation error.
- `messages` carries exactly one user turn. `{{text}}` substitution is identical
  to the other two providers, so prompt templating behaves the same everywhere.
- `max_tokens` is **required** by this API — a request without it is rejected.
  Per Clarifications it is a fixed constant, `8192` (see R9).
- **`temperature` is deliberately absent.** Per Clarifications, the Opus 4.7/4.8,
  Opus 5, Sonnet 5 and Fable 5 generation reject `temperature`, `top_p`, and
  `top_k` with HTTP 400. Older models — including `claude-haiku-4-5`, the
  documented default (R-default) — still accept them, so this is **not** a case
  where the default recipe would fail today. It is that the set of models
  accepting these parameters shrinks with each release, and sending
  `request.temperature` conditionally means a per-model allow-list that goes
  stale. The omission carries an inline comment naming the reason, because the
  field is present on the request object and its absence from the body otherwise
  looks like an oversight, and because a comment marked "do not fix without
  reading this" must state a premise a maintainer can actually verify.
- **No `thinking` or `effort` field is sent.** Accepted values differ per model
  (some reject `disabled`, some cap it by effort level), so sending any value
  reintroduces the per-model allow-list that Clarifications rejected for
  `temperature`. Each model's own default applies; `max_tokens` is sized to leave
  room for it (R9).

**Alternatives considered**:
- *Send `temperature` only to models that accept it*: rejected in Clarifications —
  the allow-list goes stale on every model release and fails hard mid-run.
- *Send `thinking: {"type": "disabled"}` to suppress reasoning*: rejected — it is
  a 400 on some current models and effort-capped on others, and the reasoning
  filter (R5) already makes the response safe regardless.

---

## R5: Response text extraction (the load-bearing decision)

**Decision**: `content` is an array of typed blocks. Concatenate, in order, the
`text` of blocks whose `type` is exactly `"text"`. Every other block type —
including `thinking` and `redacted_thinking` — is skipped.

**Rationale**: This is the direct analogue of Gemini's
`parts.filter { $0["thought"] as? Bool != true }`, and it is the highest-risk
requirement in the feature (FR-008, SC-005). Two things make it more dangerous
here than in Gemini:

1. Reasoning is **on by default** on the Claude 5 tier. A user who configures
   `claude-opus-5` rather than the documented `claude-haiku-4-5` gets reasoning
   blocks without opting in, and the system deliberately sends no `thinking`
   field to stop it (R4).
2. A failure is **silent corruption**, not a visible error: unfiltered reasoning
   would be typed straight into the user's document in place of their selection.

Allow-listing `"text"` rather than deny-listing `"thinking"` is the safer
direction: an unrecognised future block type is skipped rather than written.
Indexing `content[0]` is specifically forbidden, because a reasoning block can
legitimately precede the answer.

**Alternatives considered**:
- *Deny-list `thinking` and take everything else*: rejected — a new block type
  ships and lands in the user's document.
- *Take `content[0].text`*: rejected — wrong whenever a reasoning block comes
  first, which is the default case on current flagship models.

---

## R6: Failure mapping

**Decision**: Every outcome maps to an existing `ProviderError` case. **No new
error cases are needed** — `responseBlocked(reason:)` and `emptyResponse` were
both added by 004 and already exist, so `AIProvider.swift` is untouched by this
feature.

| Anthropic outcome | Detection | `ProviderError` | Retryable |
|---|---|---|---|
| Success | HTTP 200, ≥1 `text` block with content | *(returns text)* | — |
| Length-truncated but non-empty | `stop_reason == "max_tokens"`, text non-empty | *(returns text — success)* | — |
| Model declined | `stop_reason == "refusal"` | `.responseBlocked(reason:)` | No |
| Other non-normal stop | `stop_reason` present and not `end_turn`/`max_tokens`/`stop_sequence` | `.responseBlocked(reason: stop_reason)` | No |
| Empty after filtering | no `text` block, or all empty | `.emptyResponse` | No |
| Unparseable body | JSON decode fails, or `content` missing | `.invalidResponse` | No |
| Missing/blank key | `keychainKey` nil/empty, or Keychain throws, or value empty | `.apiKeyMissing` | No |
| 401 `authentication_error` | HTTP status | `.apiError(401, …)` | No |
| 403 `permission_error` | HTTP status | `.apiError(403, …)` | No |
| 404 `not_found_error` (unknown model) | HTTP status | `.apiError(404, …)` | No |
| 400 `invalid_request_error` | HTTP status | `.apiError(400, …)` | No |
| 413 `request_too_large` | HTTP status | `.apiError(413, …)` | No |
| 429 `rate_limit_error` | HTTP status | `.apiError(429, …)` | **Yes** |
| 500 `api_error` | HTTP status | `.apiError(500, …)` | **Yes** |
| 529 `overloaded_error` | HTTP status | `.apiError(529, …)` | **Yes** |
| Timeout / cancel / transport | thrown by `URLSession` | `mapTransportError(_:)` | per existing rules |

**The retry column requires no code.** `ProviderError.isRetryable` already
returns true for 408, 429, and 5xx-except-501. Anthropic's 529 `overloaded_error`
falls inside `500...599` and therefore retries correctly with no change to
`ActionEngine` or the shared classifier (FR-011). 413 is a 4xx and correctly does
not retry — a resend of an over-large request fails identically.

**Blocking on any non-normal `stop_reason`, not just `refusal`**: mirrors
Gemini's treatment of any `finishReason` outside `STOP`/`MAX_TOKENS`. It means
`pause_turn` and `tool_use` — which should be unreachable because this feature
sends no tools — surface as a specific reported reason rather than a confusing
empty result. The check is guarded on `stop_reason` being present, so a body
without one falls through to text extraction rather than erroring.

**Refusal reason detail**: when `stop_details.category` is present it is used as
the reason (e.g. `refusal (cyber)`), otherwise the bare `stop_reason`. The
sibling `stop_details.explanation` is **deliberately not used**: it is a
server-authored prose string that may echo fragments of the submitted text, and
`errorDescription` interpolates the reason into a user-visible message. Category
is a short fixed enum and is safe.

---

## R7: Error body shape

**Decision**: Reuse `OpenAICompatibleProvider.extractErrorMessage(from:)`
unchanged for all non-200 responses.

**Rationale**: Anthropic's error envelope is
`{"type": "error", "error": {"type": "...", "message": "..."}}`. The existing
helper already reads `error.message`, with a raw-body fallback, an empty-body
placeholder, and truncation to 200 characters. That is exactly the shape needed,
so this is a reuse rather than new code — the same reuse `GeminiProvider` makes,
and the reason its doc comment says the helper is shared.

**Alternatives considered**:
- *Write an Anthropic-specific extractor to also surface `error.type`*: rejected —
  `error.type` is redundant with the HTTP status already carried by
  `.apiError(statusCode:)`, and duplicating the helper for no new information is
  the kind of speculative code Principle VII rules out.

---

## R8: Timeout, cancellation, and logging

**Decision**: Identical to `GeminiProvider`. An ephemeral
`URLSessionConfiguration` with both `timeoutIntervalForRequest` and
`timeoutIntervalForResource` set from `config.timeoutSeconds`. Transport failures
go through `ProviderError.mapTransportError(_:)` so Escape-cancellation and
timeout stay distinguishable from other network faults. The provider logs
nothing itself; `ActionEngine` logs failures via `ProviderError.logLabel`, never
`errorDescription`.

**Rationale**: FR-014, FR-016, Principle V and VI. `logLabel` for an
`.apiError` is `"HTTP <status>"` with the server message dropped, which matters
here because that message is attacker- and model-influenced text that could echo
the user's selection.

---

## R9: The `max_tokens` constant

**Decision**: `8192`, as a private static constant on the provider.

**Rationale**: Settled in Clarifications as a fixed system-defined value. `8192`
specifically because it must satisfy four constraints at once:

1. **Large enough** that a realistic selection rewrite is never truncated — far
   beyond any in-place edit of a text selection.
2. **Below the streaming threshold.** Non-streaming requests risk transport
   timeouts at large output sizes; the vendor guidance puts that boundary around
   16000 tokens. This provider is deliberately non-streaming (out of scope per
   the spec Assumptions), so staying well under that line matters.
3. **Leaves reasoning headroom.** `max_tokens` caps reasoning *plus* answer text
   together. On a model that reasons by default, a tight limit could spend the
   whole budget before producing an answer, yielding a truncated or empty result.
4. **Within every current model's output cap.** `claude-haiku-4-5` caps at 64K
   and the Sonnet/Opus tier at 128K, so `8192` is comfortably valid on all of
   them.

**Known limitation**: long-retired models with a 4096-token output cap would
reject `max_tokens: 8192` with a 400. Those models are out of scope (spec
Assumptions exclude non-current models) and the failure is a specific, reported
`.apiError(400, …)` rather than a silent problem, so it is accepted rather than
guarded against.

---

## R10: Settings UI exposure

**Decision**: Add `.anthropic` to `ProvidersTab.selectableKinds`, drop the
`(not implemented)` suffix from `kindLabel(_:)`, and extend the base-URL
placeholder hint (currently a two-way `kind == .gemini ? … : …`) into a switch
covering all three implemented kinds.

**Rationale**: FR-002. This is the one place this feature exceeds 004's footprint:
Gemini was added when the Providers tab already listed it, whereas Anthropic is
presently hidden from the picker and labelled not-implemented. Leaving the label
would ship a working backend that the UI actively tells users is unavailable.
`SettingsViewModel.saveProvider(...)` is kind-agnostic and needs no change.

**Alternatives considered**:
- *Leave the UI alone and document config-file editing only*: rejected — FR-002
  requires it, and the current label would be actively false.

---

## Open questions

None. All Technical Context items are resolved.

## Source

Anthropic Messages API reference (`POST /v1/messages`): request and response
shape, required `max_tokens`, top-level `system`, typed `content` blocks,
`stop_reason` and `stop_details` values, error envelope, and HTTP status
semantics — `https://platform.claude.com/docs/en/api/messages`, together with
Anthropic's published model reference for per-model output caps and rejected
sampling parameters. Retrieved 2026-08-06.
