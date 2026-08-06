# Phase 0 Research: Local Ollama Model Support

**Feature**: `008-ollama-provider` | **Date**: 2026-08-06

Sources: Ollama's published API reference (`docs.ollama.com/api/chat`,
`/api/streaming`, `/api/openai-compatibility`), the existing provider
implementations in this repository, and two local probes recorded below. Every
decision that ends in an inline code comment is marked so, because the
constitution forbids "simplifying" such code away without fresh evidence.

Local environment observed while planning: `ollama` client `0.32.5` installed at
`/opt/homebrew/bin/ollama`; the server was **not running**
(`curl http://localhost:11434/api/version` → exit 7, connection refused), so no
model inventory could be read. Starting the service and pulling a model are
prerequisites of the acceptance run, not of the build.

---

## R1. Endpoint and transport

**Decision**: `POST {base}/api/chat` with `"stream": false`. Default base is
`http://localhost:11434` when the provider record sets no `baseURL`.

**Rationale**: `/api/chat` is Ollama's own chat endpoint and is the one that
carries `message.thinking` separately from `message.content` (see R5), which is
what clarification 1 selected it for. Streaming defaults to `true` on this
endpoint, and a streamed response is newline-delimited JSON objects rather than
one document; FR-010 requires a single complete answer, so `stream: false` is
mandatory, not stylistic. Omitting it would make the response body unparseable
by a single `JSONSerialization.jsonObject` call and could write a fragment.

**Alternatives considered**: `/v1/chat/completions` (Ollama's OpenAI-compatible
surface) — rejected in clarification 1: it folds reasoning into the answer and
returns generic errors. `/api/generate` — rejected: it takes a single prompt
string and has no role separation, so the action's system prompt could not be
sent as a system message.

**Inline comment required**: yes, on `stream: false`.

## R2. Request body

**Decision**:

```json
{
  "model": "<resolved model>",
  "messages": [
    { "role": "system", "content": "<action.systemPrompt>" },
    { "role": "user",   "content": "<rendered userPromptTemplate>" }
  ],
  "stream": false,
  "options": { "temperature": <action.temperature>, "num_ctx": 16384 }
}
```

**Rationale**: `model` and `messages` are the only required fields per the
published `ChatRequest` schema. Unlike Anthropic, Ollama takes the system prompt
as a normal message with `role: "system"`, so no top-level `system` field exists
and none is sent. Sampling and context settings live under `options`, not at the
top level.

**Alternatives considered**: putting the system text at the head of the user
message — rejected, it discards the role separation the endpoint offers and
changes prompt behaviour versus the other providers.

## R3. Context size (FR-010a)

**Decision**: `options.num_ctx = 16384`, a fixed private constant on the
provider. No configuration field, no Settings control, not derived from the
selection, not varied by model.

**Rationale**: when a prompt does not fit the model's context window the service
drops the oldest part rather than returning an error, so the model would rewrite
only part of the selection while `TextWriter` replaces all of it. That is silent
destruction of the user's text, which Principle II exists to prevent.

**Companion decision (FR-010b)**: a second constant,
`maxSafePromptTokens = 6000`, bounds the composed prompt the provider will send.
`transform(_:)` throws `inputTooLargeForContext(limit:)` before building a
request when the estimated tokens of the composed prompt (system prompt plus the
rendered user prompt) exceed it. This is a fixed constant checked
once per run, **not** the per-request characters-to-tokens sizing that
clarification 6 rejected: nothing about the request varies the value, and the
failure mode of a bad estimate is a visible refusal instead of silent text loss.

**Sizing, revised 2026-08-06 after code review.** The first version of this
research derived the bound from an English prose ratio (~2.7 characters per
token → 12000 characters against an 8192-token window). Review found two defects
in that derivation, both of which reopened the exact data-loss path the
constants exist to close:

1. **The check is script-blind.** `text.count` counts Characters. Chinese,
   Japanese and Korean tokenise at roughly 1-1.5 characters per token, so a
   12000-character CJK selection is ~8000-12000 tokens — over the 8192 window on
   its own. The prompt would be silently shortened and a partial rewrite would
   replace the whole selection.
2. **`num_ctx` covers the answer too, not just the prompt.** An in-place rewrite
   is by nature about as long as its input, so a 12000-character input needed
   roughly twice its own token count, which did not fit.

Both are fixed by sizing at the worst case rather than the typical one:
**window 16384, bound 6000 characters.** At ~1 token per character (the CJK
worst case) that is ~6000 prompt + ~6000 answer + a few hundred for the system
prompt ≈ 12200 tokens, inside 16384 with margin. English prose uses roughly a
third of the window. 6000 also stays above the 5000-character default action
cap, so an ordinary selection is never refused — only a user who raised that cap
can reach the bound.

**Accepted tradeoff**: `num_ctx` also *caps* models whose own default window is
larger, and *raises* it for models trained on a shorter one. Raising costs
KV-cache memory (a few hundred MB at this size for the small models the recipe
targets) and can degrade a model trained at 2048. Both are preferable to silent
truncation of the user's text.

**Known residual risk**, mirroring the equivalent note on
`AnthropicProvider.maxTokens`: the window is shared between the answer and any
reasoning the model emits, so a reasoning-heavy model working on a
maximum-length CJK selection could still reach the boundary. It would stop with
`done_reason: "length"` and the non-empty truncated answer would be written,
which is what all three other providers do with a length-truncated response and
what the spec's edge-case section calls for. Changing that to a typed error
would diverge from them and belongs in a spec revision.

**Inline comment required**: yes.

## R13. Token estimation and the prompt budget (added 2026-08-06, review round 4)

**Decision**: estimate tokens as the **UTF-8 byte count**, and cap the prompt at
`min(6000, window / 2 - 2 × templateOverhead)` where `window` is read once per
model from `POST /api/show` and cached, falling back to a conservative 4096 when
it cannot be established.

Both halves of this were arrived at by measurement, after a review round pointed
at the area and a first attempt at fixing it was falsified by running it.

**Measurement 1 — the tokenizer falls back to bytes.** Against Ollama 0.32.5 with
`tinyllama`, 100 randomly chosen CJK characters (300 UTF-8 bytes) were reported
as **328 evaluated tokens** — about one token per byte, not the ~1 per character
a "CJK is one token per character" rule of thumb predicts. An estimate of
`max(count, utf8.count / 3)` would have called that 100, understating the real
cost by more than 3x, in the direction that silently loses text. `utf8.count` is
the honest upper bound: a byte-level BPE token covers at least one byte.

*Consequence, accepted deliberately*: the budget is effectively in bytes, so it
allows roughly 6000 Latin characters but only ~2000 CJK ones. That asymmetry is
not an artefact of the estimate — those characters really do cost that much — and
the README states it.

**Measurement 2 — truncation happens at half the window, not at the window.**
Same setup, `tinyllama`, whose `/api/show` reports `llama.context_length: 2048`.
Prompts of increasing size, with `num_ctx: 16384` requested:

| Input characters | `prompt_eval_count` |
|---|---|
| 100 | 328 |
| 400 | 1194 |
| 800 | 1026 |
| 1200 | 1026 |
| 2000 | 1026 |
| 4000 | 1026 |

A prompt under the window is evaluated whole (400 → 1194). Above it, the server
keeps ~1026 tokens — half of 2048 — and answers from that, with no error. So the
usable prompt budget is **half** the granted window, the other half being what the
answer is generated into.

This falsified the first attempt at the fix, which compared `prompt_eval_count`
against the *full* granted window: with a real truncation reporting 1026 against
a window of 2048, the check did not fire, and a live test caught it. The budget
is now half the window, checked **before** sending, so an oversized prompt is
refused rather than detected after the fact. The post-hoc `prompt_eval_count`
check remains as a backstop against the same budget.

**Corrections from review round 5**, both of which reopened the hole this
research exists to close:

- *Failing open on an unknown window.* The first version returned the fixed 6000
  budget when `/api/show` could not answer, which is exactly the pre-fix
  behaviour: a deployment behind a proxy that routes only `/api/chat`, running a
  2048-window model, would accept a 3000-byte prompt and have it truncated in
  silence. The fallback is now a conservative 4096 window (Ollama's own default
  when a model does not specify one), so such deployments are limited rather
  than unprotected.
- *The estimate is not a bound on the whole request.* `prompt_eval_count`
  includes chat-template and special tokens that the text-only estimate cannot
  see — measured at roughly +30 (300 bytes → 328; 1200 bytes → 1194). With the
  budget at exactly half the window, a legitimate near-budget CJK prompt would
  evaluate to the same count as a truncated one, so the backstop could both
  false-positive and miss. The budget now reserves twice that overhead, which
  puts a strict gap between "largest legitimate prompt" and "truncation signal".
  A unit test asserts the gap across five window sizes rather than trusting the
  arithmetic — and it caught an off-by-one-reserve error in the first attempt at
  this fix.

**Why `/api/show` at all**: Ollama clamps `num_ctx` down to a model's own
maximum, so the requested 16384 is not what a 2048-model runs at. The lookup
carries only the model name, goes to the same endpoint as the transformation (so
no new host, FR-018), is cached per model, and is non-fatal — a failure falls
back to the fixed 6000 constant.

**Alternatives considered**: comparing `prompt_eval_count` against our own
estimate — rejected, the estimate is deliberately pessimistic for ASCII (~4x), so
an untruncated English run would look truncated. Keeping a character-based bound
and documenting the CJK gap — rejected, it leaves a reachable path to silent text
loss.

## R4. Temperature

**Decision**: send the action's `temperature` in `options.temperature`.

**Rationale**: this is the opposite of `AnthropicProvider`, and the difference
is deliberate and must be commented so it is not "harmonised" later. Anthropic
omits it because its newer models reject the field with HTTP 400. Ollama applies
`options` itself as generation parameters before the model sees them, so the
field is accepted uniformly regardless of which model is loaded. There is no
per-model allow-list risk here, so the action-level setting is honoured.

**Inline comment required**: yes, pointing at `AnthropicProvider`'s opposite
choice and why it does not apply.

## R5. Reasoning exclusion (FR-009, two layers)

**Decision, layer 1**: read the answer from `message.content` only. Never read
`message.thinking`. No `think` field is sent on the request.

**Rationale**: the published `ChatResponse` schema defines `message.thinking` as
a separate string, so reasoning that the service separates cannot reach the
document as long as the provider reads only `content`. This is the same
allow-list shape as `AnthropicProvider.extractText`, which filters to `text`
blocks rather than excluding `thinking` blocks: an unrecognised future field is
then skipped by default rather than typed into the user's document. Sending
`think: false` was rejected in clarification 2 — models that do not support the
field reject the request, which is the per-model allow-list trap feature 007
already hit.

**Decision, layer 2**: `stripLeadingReasoningBlock(_:)`, a pure static helper on
the Ollama provider, removes a reasoning block from the **start** of the trimmed
content when it is delimited by `<think>…</think>` or `<thinking>…</thinking>`.

- Only a block at the very start is removed. Models emit reasoning before the
  answer, so this is where it occurs, and the narrow rule cannot eat a
  legitimate `<think>` that a user is asking Overtype to rewrite in the middle of
  their text.
- If an opening marker is present at the start with no matching closing marker,
  the whole content is reasoning; the provider throws `.emptyResponse` rather
  than writing scratch work. Failing visibly beats corrupting the selection.
- Applies to Ollama output only. `ResponseSanitizer` is shared by all providers
  and is deliberately **not** touched (clarification 2).

**Inline comment required**: yes, on both layers.

## R6. New typed errors (FR-013, clarification 4)

**Decision**: add exactly three cases to `ProviderError` in
`Providers/AIProvider.swift`:

- `serviceUnreachable(address: String)` — the local service did not answer.
- `modelNotAvailable(model: String)` — the service answered, the model is not
  installed.
- `inputTooLargeForContext(limit: Int)` — the composed prompt exceeds
  `maxSafePromptTokens` (FR-010b, added 2026-08-06); thrown before any
  request is built.

All three are classified **non-retryable** in `isRetryable`, all three get an
`errorDescription` naming the fix, and all three get a `logLabel` (`"service
unreachable"`, `"model not available"`, `"input too large for context"`) that
carries no payload.

**Rationale**: Principle VI requires typed values rather than strings, and these
are the two failures whose fix is a user action on their own machine. Making
them permanent is a behaviour change *for Ollama only*: today a refused
connection surfaces as `URLError.cannotConnectToHost`, which
`retryableURLErrorCodes` lists as retryable. That listing stays as it is for the
other providers, because for a cloud host a refused connection really can be
transient; for a service that is not running on this machine it cannot clear
within a sub-second retry pause.

**Payload privacy**: both payloads are safe under Principle V. The address comes
from the user's own configuration and the model name from configuration too;
neither can contain selected text. `logLabel` still carries neither, matching
the existing convention that only `errorDescription` may be specific.

**Mapping rules**:

| Observed | Mapped to |
|---|---|
| `URLError.cannotConnectToHost`, `.cannotFindHost` | `serviceUnreachable(address:)`, carrying host **and port** |
| `URLError.networkConnectionLost` | `.networkError` (retryable). Excluded from the case above after review: the connection was established and then dropped, which proves the service was reachable and running |
| HTTP 404 whose error body matches "model … not found" | `modelNotAvailable(model:)` |
| Other non-200 | `apiError(statusCode:message:)` |
| `URLError.timedOut` / `.cancelled` | unchanged: `.timeout` / `.cancelled` via `mapTransportError` |

`.cannotFindHost` is included here even though `ProviderError` deliberately
excludes it from the shared retry set: for this provider a host that will not
resolve is exactly the "service not reachable at the configured address" case
the user must be told about, and the classification (non-retryable) agrees with
the shared rule anyway.

## R7. Error body shape

**Decision**: Ollama returns `{"error": "<string>"}`, not OpenAI's
`{"error": {"message": "<string>"}}`. Add
`OllamaProvider.extractErrorMessage(from:)` that reads the string shape and
falls back to `OpenAICompatibleProvider.extractErrorMessage(from:)` for anything
else (which itself falls back to a 200-character truncated raw body).

**Rationale**: reusing the OpenAI extractor alone would miss every Ollama error
and show the user a truncated raw JSON blob. The fallback chain keeps the
existing safety net rather than duplicating it.

**Model-not-installed detection**: the 404 body reads
`model "<name>" not found, try pulling it first`. Detection keys on the HTTP
status being 404 **and** the body containing `not found`; the model name in the
error is taken from the *request* (the resolved model), not parsed out of the
server string, so the typed payload cannot echo server-authored text.

## R8. Optional credential (FR-005, FR-006) — behavioural trap found

**Decision**: never throw `.apiKeyMissing`. Attempt Keychain retrieval only when
`keychainKey` is set; treat a missing entry, a Keychain error, or an empty value
as "no credential" and send no `Authorization` header. Send
`Authorization: Bearer <key>` only when a non-empty value comes back.

**Rationale, and the trap**: `SettingsViewModel.saveProvider` assigns
`keychainKey = "overtype-<slug>-key"` to every newly created provider
*unconditionally*, and only writes to the Keychain `if !apiKey.isEmpty`. So an
Ollama provider created through Settings with an empty key field has a non-nil
`keychainKey` pointing at an entry that does not exist. A provider that copied
`AnthropicProvider`'s `guard let keychainKey … else { throw .apiKeyMissing }`
shape would therefore fail every keyless run with "API Key is missing from the
Keychain" — the exact failure FR-005 forbids. The presence of `keychainKey` must
not be read as "a credential is required".

**Inline comment required**: yes, naming this Settings behaviour.

## R9. App Transport Security and cleartext `http://localhost`

**Evidence gathered**: a standalone Swift probe issuing
`URLSession.dataTask` against `http://localhost:11434/api/version` returned
`NSURLErrorDomain code=-1004` ("Could not connect to the server"), **not**
`-1022` (`NSURLErrorAppTransportSecurityRequiresSecureConnection`). Cleartext
loopback was therefore not blocked in that context.

**Decision**: do **not** pre-emptively add an `NSAppTransportSecurity`
dictionary to `Sources/Overtype/Resources/Info.plist`. Instead, verify from the
built `.app` bundle (where ATS reads the bundle's Info.plist, unlike the script
probe) as an explicit acceptance step. Add
`NSAppTransportSecurity → NSAllowsLocalNetworking = true`, with a comment naming
this feature, **only if** that run reports `-1022`.

**Rationale**: Principle III. The probe is evidence about a script context, not
about the bundle, so it is not sufficient to conclude either way; and Principle
VII's minimalism argues against adding a security exception that may be
unnecessary. `NSAllowsArbitraryLoads` is rejected outright: it would permit
cleartext to *any* host, far beyond FR-008.

**OUTCOME, 2026-08-06 — resolved, no change made.** The check was run properly:
the probe binary was placed inside `Overtype.app/Contents/MacOS/` so it read the
shipped `Info.plist`, and it was pointed at four addresses.

| Address | Result | Meaning |
|---|---|---|
| `http://localhost:11434` | HTTP 200 | Allowed |
| `http://192.168.1.50:11434` | `-1001` timed out | Allowed (nothing listening) |
| `http://10.0.0.42:11434` | `-1001` timed out | Allowed |
| `http://ollama-box.local:11434` | `-1001` timed out | Allowed |
| `http://example.com` | **`-1022`** | **Blocked by ATS** |

macOS therefore already exempts loopback, `.local`, and private LAN ranges with
no `NSAppTransportSecurity` key present, while still blocking cleartext to a
public host. **No `Info.plist` change was made and none is needed.** The `-1022`
on the public host is correct behaviour, not a defect; the README now states
that a remote Ollama on a public address must use `https`.

This also settles a question the first draft did not ask: the README recommends
pointing the provider at another machine on the network, and that path works
over plain HTTP for private addresses.

## R10. Settings Providers tab (FR-002, FR-005)

**Decision**: four small edits in `UI/Settings/ProvidersTab.swift`:

1. `selectableKinds`: add `.ollama`.
2. `kindLabel`: `"Ollama (not implemented)"` → `"Ollama"`.
3. `baseURLPlaceholder`: `"http://localhost:11434"` →
   `"Default: http://localhost:11434"`, matching the "Default:" convention that
   file already documents for kinds which fall back to a built-in host.
4. The `SecureField` prompt becomes kind-dependent so it reads as optional for
   Ollama (for example `"API Key (optional, not needed for a local service)"`).

Edit 4 is the only genuinely new UI behaviour; 1-3 correct statements this
feature makes false. No save-time validation change is needed: `saveProvider`
already accepts an empty key (see R8).

## R11. Recipe values (FR-021)

**Decision**: `defaultModel: "llama3.2"`, `timeoutSeconds: 30`, `baseURL`
omitted, `keychainKey` omitted, `retryDelaySeconds` left at the 0.5 default.

**Rationale**: model and time limit were both settled in clarification
(`llama3.2`; 30 s, changed from the suggested 120 s by the user). Because 30 s is
the cloud value and a first request may spend most of it loading the model, the
README recipe must state that a first-run timeout is expected on slower hardware
or larger models and that raising the provider's time limit (slider maximum
300 s) is the fix. The planning-time confirmation clarification 5 asked for could
not be completed offline (`ollama list` needs a running server), so it is carried
into the acceptance procedure: if `ollama pull llama3.2` fails, substitute a
model meeting the same three criteria (small, no reasoning by default, generally
available) and update the recipe.

**Shipped default config**: unchanged. `Config/DefaultConfig.swift` is not
touched, so a fresh install gains no Ollama provider and no extra shortcut.

## R12. Documentation surface

**Decision**: `README.md` line 10 currently says "(Ollama support coming soon)"
and must change; add an Ollama recipe next to the existing provider recipes.
`docs/privacy.md` gains Ollama as a destination, phrased so the local case is
explicit: with an Ollama provider the selection goes only to the configured
endpoint, which is the user's own machine in the documented setup.
`docs/compatibility.md` gains an Ollama manual acceptance section, including the
offline run (SC-004) and the ATS check from R9.

## Resolved unknowns

| Unknown from Technical Context | Resolution |
|---|---|
| Which Ollama interface, and its exact wire shape | R1, R2, `contracts/ollama-chat.md` |
| How reasoning is kept out of the document | R5 (two layers) |
| Fixed context size value | R3 (16384 window, 6000-character bound) |
| Whether new error cases are needed | R6 (two, in the shared enum) |
| How a keyless provider avoids `.apiKeyMissing` | R8 (the `keychainKey`-is-always-set trap) |
| Whether cleartext loopback needs an ATS exception | R9 — **RESOLVED 2026-08-06**: no exception needed, none added |
| Recipe model and time limit | R11 |

No `NEEDS CLARIFICATION` markers remain.
