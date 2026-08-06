# Feature Specification: Anthropic Claude Model Support

**Feature Branch**: `007-anthropic-provider`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "Add support for Anthropic Claude models as a first-class AI provider, using Anthropic's native Messages API rather than an OpenAI-compatible shim. The provider kind 'anthropic' already exists in the configuration enum but is currently a non-functional stub. A user must be able to add an Anthropic provider through the Settings Providers tab or by editing config.json, store their API key in the macOS Keychain, point any existing action at it, and have the action run end to end with no code changes and no rebuild."

## Clarifications

### Session 2026-08-06

- Q: Overtype actions carry a per-action creativity setting (temperature), but current Claude models reject that field with an HTTP 400. How should an Anthropic run handle it? → A: Never send it. Anthropic requests always omit the creativity setting, so the provider works against every current Claude model. The action-level setting continues to apply unchanged to other providers, and the reason is recorded at the point of omission so it is not "simplified" back in later. The README recipe must state that the setting does not apply to Anthropic. A per-model allow-list was rejected because it goes stale on every model release and turns into a hard request-validation failure mid-run.
- Q: Which Claude model should the documented Anthropic provider recipe use as its `defaultModel`? → A: `claude-haiku-4-5`. This follows the precedent set by 004, which chose the fast/lite tier (`gemini-3.5-flash-lite`) rather than a flagship: Overtype rewrites a selection inline while the user waits, so latency is the product. It also avoids the reasoning-leakage and budget-contention risks by default, because this model does not produce reasoning content unless asked. Users remain free to configure any Claude model, so the reasoning filter (FR-008) is still required.
- Q: Anthropic requires a response length limit on every request, and no existing provider or action field expresses one. How should it be supplied? → A: A single fixed constant defined by the provider (`8192`), with no schema change and no user-facing configuration. This mirrors how the Gemini provider hardcodes its base URL. The value is large enough to cover any realistic selection rewrite, small enough to stay below the size at which a non-streaming request risks a transport timeout, and leaves headroom on models that spend part of the same budget on reasoning. Scaling the limit from the selection length was rejected as guesswork without a tokenizer; adding a configurable field was rejected as widening the feature past the provider contract for a value no other provider uses.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run an action against a Claude model (Priority: P1)

A user who prefers Anthropic's Claude models configures an Overtype provider
that points at Anthropic, stores their Anthropic API key in the Keychain, and
attaches that provider to an action (for example "Fix grammar"). They select
text in any supported application, press the action's shortcut, and the
selection is replaced by Claude's response.

**Why this priority**: This is the core value of the feature. Without the
ability to actually send a selection to Claude and write the result back,
nothing else matters. It is a complete, demonstrable slice on its own.

**Independent Test**: Configure one Anthropic provider and one action that uses
it, select text in a known-supported app, trigger the shortcut, and confirm the
selection is replaced by a Claude-generated result with the standard
Reading / Thinking / Writing feedback.

**Acceptance Scenarios**:

1. **Given** an Anthropic provider is configured with a valid API key and an
   action is bound to it, **When** the user selects text and presses the
   action's shortcut, **Then** the selection is replaced by Claude's
   transformed text.
2. **Given** an Anthropic action is running, **When** the model is processing,
   **Then** the user sees the standard in-progress feedback (Reading, Thinking,
   Writing) exactly as with existing providers.
3. **Given** the user presses Escape while an Anthropic run is in progress,
   **When** the response has not yet been written, **Then** the run is cancelled
   and the original selection is left unchanged.

---

### User Story 2 - Choose Anthropic without writing code (Priority: P1)

A user adds Anthropic as a provider without touching source code: either by
selecting it from the provider-kind list in the Settings Providers tab, or by
declaring a provider record in the configuration file naming Anthropic as its
kind, a default model, and a Keychain reference for the key. Today the Anthropic
kind is present in configuration but is not offered in the Settings picker and is
labelled as not implemented, and a hand-written Anthropic configuration is
accepted but silently never registered, so the run fails with a generic
"provider not found" rather than doing anything useful.

**Why this priority**: The product's core promise is that new AI backends are
added by configuration, not by code. The current half-present Anthropic kind is
worse than absent, because it lets a user construct a configuration that appears
valid and then fails opaquely.

**Independent Test**: Starting from a default install, add an Anthropic provider
through the Settings Providers tab (and, separately, by editing only the
configuration file and the Keychain), then confirm an Anthropic action becomes
available and works, without touching or rebuilding the application binary.

**Acceptance Scenarios**:

1. **Given** the Settings Providers tab is open, **When** the user adds a
   provider, **Then** Anthropic is offered in the provider-kind list without a
   "not implemented" qualifier and can be saved with a key.
2. **Given** the configuration declares a provider whose kind is Anthropic,
   **When** the configuration is loaded, **Then** the provider is registered and
   selectable by actions.
3. **Given** an Anthropic provider references a model, **When** an action using
   that provider runs, **Then** the request targets the action-level model if
   set, otherwise the provider's default model.

---

### User Story 3 - Clear, specific errors for Anthropic failures (Priority: P2)

When an Anthropic request fails (invalid or missing API key, unknown model,
quota or rate limit exceeded, network failure, a response the model declined to
produce, or an empty response), the user sees a specific, human-readable error
and their original selection is untouched.

**Why this priority**: Every run must either succeed or report a specific typed
error, and the original text must survive every failure. Anthropic introduces
failure modes (a declined response, an empty response) that must map to
understandable messages rather than a silent no-op or a corrupted selection.

**Independent Test**: Trigger an Anthropic action with a deliberately invalid
API key and confirm a clear authentication error appears and the selection is
unchanged; repeat with an unknown model name.

**Acceptance Scenarios**:

1. **Given** an Anthropic provider with an invalid or missing API key, **When**
   the user triggers the action, **Then** a specific authentication error is
   shown and the selection is unchanged.
2. **Given** Anthropic returns an empty response or one the model declined to
   produce, **When** the action runs, **Then** the user sees a specific error
   explaining no usable result was produced and the selection is unchanged.
3. **Given** the network is unavailable, **When** the action runs, **Then** a
   specific network error is shown and the selection is unchanged.
4. **Given** a transient failure such as a rate limit or a server-side error,
   **When** the action runs, **Then** the existing single automatic retry applies
   exactly as it does for other providers, and a persistent failure ends in a
   specific error with the selection unchanged.

---

### Edge Cases

- What happens when the Anthropic API key is absent from the Keychain? The run
  must fail before any text is written, with a message that tells the user a key
  is required.
- How does the system handle a response the model truncates because a length
  limit was reached? A non-empty truncated result is sanitized and written like
  any other provider's output; if it is empty, it maps to the "no usable result"
  error. This matches the existing Gemini behaviour.
- **How does the system handle a response that contains model reasoning
  alongside the answer?** Claude models may return internal reasoning content in
  the same response as the answer, and on current models this can occur without
  the user opting in. Only the answer text may be written; reasoning content MUST
  NOT reach the user's document. This is the highest-risk edge case in the
  feature, because a failure here silently corrupts the user's text with model
  scratch work rather than producing a visible error.
- How does the system handle the frontmost app or focused element changing while
  Claude is still processing? The write is aborted (non-destructive re-check),
  identical to existing providers.
- What happens if the configured model name is not recognized by the service? A
  specific error identifying the problem is shown and nothing is written.
- What happens if the request omits a field the service requires, or includes a
  field the selected model rejects? The run must fail with a specific error and
  write nothing; the feature must be configured so this does not occur for the
  documented default model.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST let a user select Anthropic as the backend for an
  action through configuration alone, without any source-code change or rebuild.
- **FR-002**: The system MUST offer Anthropic as a selectable provider kind in
  the Settings Providers tab, labelled without any "not implemented" qualifier,
  and MUST accept and store an Anthropic provider saved from that tab.
- **FR-003**: The system MUST send the action's prompt and the selected text to
  the configured Claude model and return the model's text response into the
  existing run pipeline (read → call → sanitize → context re-check → write).
- **FR-004**: The system MUST resolve the model for an Anthropic run using the
  existing order: the action-level model if present, otherwise the provider's
  `defaultModel`. The documented Anthropic provider recipe MUST use
  `claude-haiku-4-5` as its `defaultModel`; the value is supplied entirely by the
  user's configuration, and no code hard-codes an Anthropic-specific model. Any
  Claude model the user configures MUST work, including models that return
  reasoning content (see FR-008).
- **FR-005**: The system MUST read the Anthropic API key only from the macOS
  Keychain, referenced by the provider's Keychain key. The key MUST NOT be
  written to configuration, logs, error messages, the request URL, or the user
  interface.
- **FR-006**: The system MUST supply every field the Anthropic service requires
  on a request, including a response length limit, without requiring the user to
  configure a value that the existing provider and action records cannot express.
  The response length limit MUST be a single fixed value defined by the system,
  MUST be large enough that a realistic selection rewrite is not truncated, and
  MUST leave headroom for models that consume part of the same budget on
  reasoning. It MUST NOT introduce a configuration field or a Settings control.
- **FR-007**: The system MUST NOT send request fields that current Claude models
  reject, so that a correctly configured provider succeeds against the documented
  default model rather than failing with a request-validation error.
  Specifically, an Anthropic request MUST NOT carry the action's creativity
  (temperature) setting under any circumstance, including when the action
  explicitly sets one. The system MUST NOT maintain a per-model allow-list for
  this field. The action-level setting remains in effect for all other providers.
- **FR-008**: The system MUST extract only answer text from the model's response
  and MUST NOT write model reasoning content into the user's document.
- **FR-009**: The system MUST show the same in-progress and success feedback for
  Anthropic runs as for existing providers, and MUST NOT take keyboard focus
  during a run.
- **FR-010**: The system MUST report Anthropic failures as specific, typed,
  human-readable errors, distinguishing at minimum: missing or invalid
  credentials, unknown or unavailable model, quota or rate limiting, network
  failure, a declined response, and an empty response.
- **FR-011**: The system MUST classify Anthropic failures as retryable or not
  using the existing shared retry rules, so that transient failures receive the
  existing single automatic retry and deterministic failures do not.
- **FR-012**: The system MUST leave the user's selection unchanged on every
  Anthropic failure path, and MUST abort the write if the target context changed
  since the selection was read.
- **FR-013**: The system MUST apply the existing response sanitization to
  Anthropic output before writing, so behavior matches other providers.
- **FR-014**: An Anthropic run MUST be cancellable by the user and MUST enforce a
  hard timeout, consistent with existing providers.
- **FR-015**: The system MUST NOT contact any endpoint other than the Anthropic
  service when an Anthropic action is invoked, and MUST NOT emit telemetry.
- **FR-016**: The selected text and Claude's output MUST NOT appear in logs at
  the default log level; they MAY appear only under debug logging.
- **FR-017**: The compatibility and privacy documentation MUST be updated to
  record Anthropic as an available provider and to state that selected text is
  sent to Anthropic's endpoint when an Anthropic action is used.
- **FR-018**: The README MUST document a copy-ready recipe for enabling Anthropic
  (a provider block naming the Anthropic kind with a default model, plus how to
  store the key in the Keychain) and MUST no longer describe Anthropic support as
  forthcoming. The shipped default configuration MUST remain unchanged, so a
  fresh install adds no Anthropic provider, no keyless provider entry, and no
  extra global shortcut.

### Key Entities *(include if data involved)*

- **Anthropic Provider (configuration record)**: A provider entry whose kind
  identifies it as Anthropic. Attributes: identifier, kind, endpoint/base
  reference, default model, timeout, retry delay, and Keychain key reference. It
  carries no secret value itself.
- **Anthropic API Key (secret)**: The user's Anthropic credential, stored only in
  the macOS Keychain and referenced by the provider record.
- **Action (existing)**: An automation record that may name an Anthropic provider
  and, optionally, a specific Claude model.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can enable Anthropic and run a successful transformation by
  choosing the provider kind in Settings and storing one key, or by editing only
  configuration and storing one key, without rebuilding the app, in under
  5 minutes.
- **SC-002**: 100% of Anthropic failure cases in the acceptance scenarios
  (invalid key, unknown model, network failure, declined or empty response)
  produce a specific human-readable error and leave the selection unchanged.
- **SC-003**: For a typical short selection, a successful Anthropic run completes
  and writes the result with the same visible feedback stages as existing
  providers, with no perceptible difference in interaction.
- **SC-004**: Across the full test suite, the selected text and model output
  never appear in any log at the default level, and the Anthropic API key never
  appears in configuration, logs, the request address, or the interface.
- **SC-005**: In 100% of responses that carry model reasoning alongside the
  answer, only the answer text is written to the user's document.
- **SC-006**: Adding Anthropic required no change to any existing action's
  behavior; all previously configured providers and actions continue to work
  unchanged.

## Assumptions

- Authentication uses a single Anthropic API key obtained by the user from the
  Anthropic Console, stored in the Keychain like other provider keys. OAuth,
  workload identity federation, and the cloud-marketplace variants of the service
  (Amazon Bedrock, Google Vertex AI, Microsoft Foundry) are out of scope for this
  feature; those use different authentication and different model identifiers.
- Only text-in / text-out transformations are in scope. Multimodal inputs
  (images, documents), tool use, and streaming partial output are out of scope
  for this feature.
- Anthropic is reached over the network as a hosted service; local execution is
  not part of this feature.
- The existing run pipeline, feedback HUD, cancellation, timeout, retry,
  sanitization, and Keychain storage are reused as-is; this feature adds
  Anthropic as another backend within that pipeline rather than changing the
  pipeline.
- The required response-length limit (FR-006) is a fixed feature-level value
  rather than new user-facing configuration (resolved in Clarifications), because
  the existing provider and action records have no field expressing it and the
  transformations in scope are short in-place rewrites of a selection. Adding a
  user-configurable limit is deliberately deferred.
- No reasoning or effort configuration is sent on an Anthropic request. The
  system neither enables nor disables reasoning explicitly, for the same reason
  it omits the creativity setting: the accepted values differ per model, so
  sending any value reintroduces a per-model allow-list that goes stale. Each
  model's own default applies, and the fixed response-length limit is sized to
  leave room for it.
- The per-action creativity setting is never transmitted to Anthropic (FR-007,
  resolved in Clarifications). Users who set it on an Anthropic action will see
  it ignored; the README recipe must say so.
- Anthropic is added via the Settings picker and a documented configuration
  recipe rather than pre-seeded in the shipped default config; the default
  first-run configuration is unchanged by this feature, matching how Gemini was
  added.
