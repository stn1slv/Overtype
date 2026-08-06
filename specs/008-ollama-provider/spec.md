# Feature Specification: Local Ollama Model Support

**Feature Branch**: `008-ollama-provider`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "Add support for the Ollama provider, so users can run text transformations against a locally hosted Ollama model instead of a cloud API."

## Clarifications

### Session 2026-08-06

- Q: Should an Ollama run talk to the service through Ollama's own chat interface, or through the OpenAI-style interface that Ollama also exposes? → A: A dedicated Ollama backend using Ollama's own chat interface. Reasoning content arrives in its own field rather than mixed into the answer text, so the highest-risk failure in this feature (model scratch work silently written into the user's document) is prevented at the source instead of by pattern-matching the answer. Local setup failures also carry the service's own wording, which is what makes a specific "model not installed" message possible. The cost is a new provider type to maintain. Reusing the OpenAI-compatible backend was rejected because it folds reasoning into the answer text and returns generic errors for exactly the failures User Story 3 exists to make clear.

- Q: Some locally runnable models put their reasoning in a separate field, but others wrap it in markers inside the answer text. How far should the system go to keep that reasoning out of the user's document? → A: Two layers, scoped to Ollama runs. The separate field is authoritative where the service provides it, and in addition clearly marked reasoning blocks are removed from the answer text before it is written. The removal applies to Ollama output only, so the three existing providers keep their current behaviour. Asking the service to disable reasoning per request was rejected for the same reason feature 007 rejected sending the creativity setting to Anthropic: models that do not support the setting reject the whole request, which reintroduces a per-model allow-list that goes stale on every model release.

- Q: In the Settings Providers tab, how should the API key field behave when the selected provider kind is Ollama? → A: Shown but marked optional, with a hint that a local service needs none. A credential is sent only when the user actually stored one; an empty field is a valid, fully supported configuration and must never produce a missing-credential error. Hiding the field was rejected because it would leave users whose Ollama sits on another machine behind a login unable to use the Ollama kind at all; requiring it was rejected because it would block the normal local setup that the feature exists for.

- Q: When the local service cannot be reached, or the requested model was never downloaded, should those become new named error kinds in the shared error type, or be reported through the existing kinds with a different message? → A: Two new named error kinds in the shared error type, one carrying the address that could not be reached and one carrying the model name that is not installed. Both are classified as permanent, so neither consumes the single automatic retry: a service that is not running will not have started within the retry pause, and a model that is not downloaded will not appear on a second identical request. Reusing the existing kinds was rejected because it moves the cause into a message string, which the constitution's typed-error rule forbids; a single combined kind was rejected because the two causes could then not be classified or tested apart.

- Q: Which locally installed model should the README recipe use as its default? → A: `llama3.2`. It is small, widely distributed, fast enough on a laptop for an inline rewrite, and does not emit reasoning by default. This follows the precedent of the Gemini and Anthropic recipes, which both chose the fast tier over a flagship because Overtype rewrites a selection while the user waits, so latency is the product. Planning MUST confirm the name is still one the service distributes; if it is not, the substitute must meet the same three criteria (small, no reasoning by default, generally available). Users remain free to configure any installed model, so the reasoning filter (FR-009) is still required.

- Q: Should an Ollama request ask the service for a specific context size, or accept whatever the loaded model defaults to? → A: Ask for a single fixed context size on every Ollama request, defined by the system with no configuration field and no per-model logic, sized to hold the largest allowed selection plus a full answer. This mirrors how the Anthropic provider supplies its own required response-length limit as a fixed constant. The reason is non-destructiveness: when a prompt does not fit the context window the service drops the oldest part instead of reporting an error, so the model would rewrite only part of the selection while Overtype replaces all of it, silently losing the user's text. Relying on the model default plus the existing per-action character cap was rejected because the safety would depend on the user never raising that cap; deriving the size from the cap per request was rejected as the same characters-to-tokens guesswork feature 007 already rejected. The exact value is chosen during planning.

- Q: After a run finishes, should Overtype ask the service to keep the model loaded in memory for longer than it normally would? → A: No. Overtype sends nothing about how long the model stays resident and accepts the service's own idle policy. Holding gigabytes of memory between runs is a side effect the user did not ask for and cannot observe from inside Overtype, and the service already exposes its own setting for users who want it. The README recipe points at that setting and states that the first run after an idle pause is slower because the model is being loaded. A Settings control for it was rejected as a configuration field almost no user would touch.

- Q: What time limit should the README recipe give the Ollama provider? → A: 30 seconds, the same value the existing cloud recipes use. (120 seconds was suggested and initially accepted, then changed to 30 by the user; recorded here so the tradeoff is not re-litigated.) The tradeoff is explicit: 30 seconds is ample once the model is resident, but a first run that must read a large model into memory can exceed it and end in the standard timeout error, leaving the selection unchanged. Because of that, the README recipe MUST state that a timeout on the first run after an idle pause is expected on slower hardware or larger models, and that raising the provider's time limit (the Settings slider accepts up to 300 seconds) is the fix. This is a documentation and configuration value only: no new field, and no change to how the existing time limit behaves.

- Q: The fixed context size holds a selection up to the default limit of 5,000 characters. What should happen if a user raises an action's character limit past what that context size can hold? → A: Keep the promise absolute: refuse the run with a specific error before anything is sent, rather than narrowing the promise to the default limit. The check compares the actual selection against a fixed, conservative character bound derived once from the context size, so it is a constant rather than the per-request characters-to-tokens estimate rejected in an earlier clarification, and erring low only means refusing slightly early. Narrowing the guarantee to the default limit was rejected because it leaves a configuration the user can reach that quietly loses their text; raising the context size to cover the largest limit the Settings slider allows was rejected because every run would then reserve memory for a worst case that almost never occurs. (Recorded in response to a cross-artifact analysis finding that FR-010a's original absolute wording was not backed by the design.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run an action against a local model (Priority: P1)

A user who runs Ollama on their own Mac configures an Overtype provider that
points at that local service and attaches it to an action (for example "Fix
grammar"). They select text in any supported application, press the action's
shortcut, and the selection is replaced by the local model's response. No
account, no API key, and no cloud service are involved.

**Why this priority**: This is the core value of the feature. Without the
ability to send a selection to a locally running model and write the result
back, nothing else matters. It is a complete, demonstrable slice on its own.

**Independent Test**: With Ollama running locally and one model already
installed, configure one Ollama provider and one action that uses it, select
text in a known-supported app, trigger the shortcut, and confirm the selection
is replaced by a locally generated result with the standard Reading / Thinking /
Writing feedback.

**Acceptance Scenarios**:

1. **Given** the local model service is running with the configured model
   installed and an action is bound to an Ollama provider, **When** the user
   selects text and presses the action's shortcut, **Then** the selection is
   replaced by the model's transformed text.
2. **Given** an Ollama action is running, **When** the model is processing,
   **Then** the user sees the standard in-progress feedback (Reading, Thinking,
   Writing) exactly as with existing providers.
3. **Given** the user presses Escape while an Ollama run is in progress,
   **When** the response has not yet been written, **Then** the run is cancelled
   and the original selection is left unchanged.

---

### User Story 2 - Choose Ollama without writing code and without a key (Priority: P1)

A user adds Ollama as a provider without touching source code: either by
selecting it from the provider-kind list in the Settings Providers tab, or by
declaring a provider record in the configuration file naming Ollama as its kind
and a model. Because the service runs on the user's own machine, no credential
is required and the Settings form must not demand one. Today the Ollama kind is
present in configuration but is hidden from the Settings picker, is labelled as
not implemented, and a hand-written Ollama configuration is accepted but
silently never registered, so the run fails with a generic "provider not found"
rather than doing anything useful.

**Why this priority**: The product's core promise is that new AI backends are
added by configuration, not by code. The current half-present Ollama kind is
worse than absent, because it lets a user construct a configuration that appears
valid and then fails opaquely. A key field that appears mandatory would also
block the normal, keyless local setup.

**Independent Test**: Starting from a default install, add an Ollama provider
through the Settings Providers tab leaving the credential field empty (and,
separately, by editing only the configuration file), then confirm an Ollama
action becomes available and works, without touching or rebuilding the
application binary.

**Acceptance Scenarios**:

1. **Given** the Settings Providers tab is open, **When** the user adds a
   provider, **Then** Ollama is offered in the provider-kind list without a
   "not implemented" qualifier and can be saved with no credential entered.
2. **Given** the configuration declares a provider whose kind is Ollama,
   **When** the configuration is loaded, **Then** the provider is registered and
   selectable by actions.
3. **Given** an Ollama provider is saved with its endpoint field left empty,
   **When** an action using it runs, **Then** the request goes to the documented
   default local address for the service.
4. **Given** an Ollama provider references a model, **When** an action using
   that provider runs, **Then** the request targets the action-level model if
   set, otherwise the provider's default model.

---

### User Story 3 - Clear, specific errors for local failures (Priority: P2)

When an Ollama request fails, the user sees a specific, human-readable error and
their original selection is untouched. The failures that matter here are
different from a cloud provider's: the service may not be running at all, the
requested model may not have been downloaded yet, or a first request may spend a
long time loading a large model into memory.

**Why this priority**: Every run must either succeed or report a specific typed
error, and the original text must survive every failure. A local backend
introduces setup failures that a generic "network error" would leave the user
unable to diagnose, because the fix is a local action (start the service, or
download the model) rather than a retry.

**Independent Test**: Stop the local model service and trigger an Ollama action;
confirm a specific error says the service could not be reached and the selection
is unchanged. Repeat with the service running but a model name that has not been
downloaded.

**Acceptance Scenarios**:

1. **Given** the local model service is not running, **When** the user triggers
   an Ollama action, **Then** a specific error states that the local service
   could not be reached at its configured address, and the selection is
   unchanged.
2. **Given** the service is running but the configured model is not installed
   locally, **When** the action runs, **Then** a specific error identifies the
   missing model and the selection is unchanged.
3. **Given** the model returns an empty result, **When** the action runs,
   **Then** the user sees a specific error explaining no usable result was
   produced and the selection is unchanged.
4. **Given** a run exceeds the provider's configured time limit (for example
   while a large model is loading for the first time), **When** the limit is
   reached, **Then** the run ends with the standard timeout error and the
   selection is unchanged.

---

### User Story 4 - Keep the text on the machine (Priority: P3)

A user with confidential text chooses an Ollama action precisely because nothing
leaves their Mac. Running that action sends the selection only to the configured
local address, and it works with the machine disconnected from the internet.

**Why this priority**: Local-only processing is the reason to prefer this
backend over the existing cloud providers. It is lower priority than P1/P2 only
because it is a property of the same code path rather than separate
functionality, but it must be verified and documented, because a user who
believes their text stays local and is wrong is materially harmed.

**Independent Test**: Disconnect the machine from all networks, run an Ollama
action, and confirm it completes successfully; separately, observe that the only
address contacted during a run is the configured local one.

**Acceptance Scenarios**:

1. **Given** the machine has no internet connection and the local service is
   running, **When** the user triggers an Ollama action, **Then** the run
   completes successfully and the selection is replaced.
2. **Given** an Ollama action runs, **When** the run completes, **Then** no
   address other than the provider's configured endpoint was contacted.
3. **Given** the user reads the project documentation, **When** they look up
   which data leaves the machine, **Then** the documentation states that with an
   Ollama provider the selected text is sent only to the configured local
   endpoint.

---

### Edge Cases

- What happens when the local model service is not installed or not running? The
  run must fail before any text is written, with a message that names the
  address that could not be reached, so the user knows to start the service or
  correct the address.
- What happens when the configured model has not been downloaded locally? The
  run must fail with a message identifying the model, so the user knows to
  install it. The system must not download models on the user's behalf: a model
  download is large and slow, and starting one silently in the middle of a text
  transformation would be an unexpected, unbounded action.
- **How does the system handle a response that contains model reasoning
  alongside the answer?** Many locally runnable models emit internal reasoning
  before their answer, and some do so without being asked. Only the answer text
  may be written; reasoning content MUST NOT reach the user's document. This is
  the highest-risk edge case in the feature, because a failure here silently
  corrupts the user's text with model scratch work rather than producing a
  visible error.
- What happens on the first request after the machine boots, when the model must
  be loaded into memory? The request may take far longer than a cloud call. It is
  bounded by the provider's existing time limit and ends in the standard timeout
  error rather than hanging; the documented recipe uses a longer time limit than
  the cloud defaults so that a normal first load is not cut short.
- How does the system handle the frontmost app or focused element changing while
  the local model is still generating? The write is aborted (non-destructive
  re-check), identical to existing providers.
- What happens when the user points the provider at a service on another machine
  on the local network, or at a hosted service that requires a credential? The
  configured address is used as given, and if the user has stored a credential
  for that provider it is sent; the run must not fail merely because the address
  is not the local default.
- What happens when the selection is larger than the action permits? The run
  stops before any request is made and the user is told the selection is too
  large. This is existing behaviour shared by all providers and is unchanged
  here; FR-010a exists so that a selection which passes that check is never
  silently shortened afterwards by the service.
- What happens when the user raises an action's character limit above what the
  fixed context size holds, and then selects that much text? The selection
  passes the action's own limit but is refused by the provider before any
  request is sent, with an error naming the setting to lower (FR-010b). Nothing
  is written and nothing is retried. Without this second check the service would
  quietly shorten the input and the model would rewrite only part of the
  selection while the whole selection was replaced.
- What happens when the configured address uses a plain, non-encrypted local
  connection? This is the normal case for a service on the user's own machine and
  MUST work without the user having to change any system or application setting.
- How does the system handle a response that the model truncates because a length
  limit was reached? A non-empty truncated result is sanitized and written like
  any other provider's output; if it is empty, it maps to the "no usable result"
  error. This matches existing provider behaviour.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST let a user select Ollama as the backend for an
  action through configuration alone, without any source-code change or rebuild.
- **FR-002**: The system MUST offer Ollama as a selectable provider kind in the
  Settings Providers tab, labelled without any "not implemented" qualifier, and
  MUST accept and store an Ollama provider saved from that tab.
- **FR-003**: The system MUST send the action's prompt and the selected text to
  the configured local model and return the model's text response into the
  existing run pipeline (read → call → sanitize → context re-check → write).
- **FR-004**: The system MUST resolve the model for an Ollama run using the
  existing order: the action-level model if present, otherwise the provider's
  `defaultModel`. Any model the user has installed locally MUST work, including
  models that emit reasoning content (see FR-009). No code may hard-code an
  Ollama-specific model name; the documented recipe supplies the value through
  configuration.
- **FR-005**: The system MUST NOT require a credential for an Ollama provider.
  Saving an Ollama provider with an empty credential field MUST succeed, and a
  run against a keyless provider MUST NOT fail with a missing-credential error.
  The Settings credential field MUST remain visible for the Ollama kind and MUST
  be presented as optional, with a hint that a service on the user's own machine
  needs none.
- **FR-006**: If the user has stored a credential for an Ollama provider (for a
  remote or authenticated deployment), the system MUST send it and MUST read it
  only from the macOS Keychain. The credential MUST NOT be written to
  configuration, logs, error messages, the request address, or the user
  interface.
- **FR-007**: The system MUST use a documented default local address when the
  provider's endpoint field is empty, and MUST use the user's value when it is
  set, allowing a non-default port or a host other than the local machine.
- **FR-008**: The system MUST be able to reach a service on the user's own
  machine over a plain, non-encrypted local connection, without requiring the
  user to change any system or application setting.
- **FR-009**: The system MUST extract only answer text from the model's response
  and MUST NOT write model reasoning content into the user's document. Where the
  service reports reasoning separately from the answer, the system MUST take the
  answer from that separate field rather than inferring the boundary from the
  answer text. Where a model instead marks a reasoning block inside the answer
  text, the system MUST remove that block before writing. This removal MUST
  apply to Ollama output only and MUST NOT change what any existing provider
  writes. The system MUST NOT ask the service to disable reasoning on a request,
  because models that do not accept that instruction reject the whole request.
- **FR-010**: The system MUST receive the model's answer as a single complete
  response, so the text written to the document is the whole answer and never a
  partial fragment.
- **FR-010a**: The system MUST request a context size large enough that a
  selection, together with the prompt and a full answer, is never dropped by the
  service before the model sees it. The value MUST be a single fixed
  system-defined constant: it MUST NOT introduce a configuration field or a
  Settings control, MUST NOT be derived from the length of the selection, and
  MUST NOT vary by model.
- **FR-010b**: Because an action's character limit is user-adjustable and can be
  raised above what that fixed context size holds, the system MUST refuse an
  Ollama run, before sending anything, when the selection is larger than the
  context size can safely hold. The refusal MUST be a specific, typed,
  human-readable error stating the limit and an action the user can actually
  take, MUST leave the selection unchanged, and MUST NOT be retried. The bound
  it compares against MUST be a fixed conservative constant derived once from
  the context size **or from the window the model actually reports**, and MUST
  be measured against what is actually sent to the model (the action's prompt
  with the selection substituted, plus the system prompt) rather than against
  the selection alone. It MUST NOT vary with the content of an individual
  request.

  (Revised again 2026-08-06, review round 5: the original wording forbade
  per-model logic outright. Measurement showed a fixed constant cannot hold the
  guarantee — the service clamps the context window to the model's own maximum
  and then truncates an over-long prompt to half of it, silently — so the bound
  is now the smaller of the fixed constant and half the window the model
  reports. That is still fixed per model rather than per request, which is what
  the original restriction was protecting against.)
  (Revised 2026-08-06: the original wording required the message to name the
  action's Max Characters setting. Implementation review established that
  lowering that setting cannot make the run succeed — it makes the same
  selection fail earlier with a different message — so naming it was misleading
  advice.)
- **FR-011**: The system MUST NOT download, install, or otherwise modify the
  user's locally installed models, and MUST NOT start or stop the local service.
  Its only interaction with the service is issuing the transformation request.
  In particular, the system MUST NOT instruct the service how long to keep a
  model resident in memory; that policy stays with the service and its own
  settings.
- **FR-012**: The system MUST show the same in-progress and success feedback for
  Ollama runs as for existing providers, and MUST NOT take keyboard focus during
  a run.
- **FR-013**: The system MUST report Ollama failures as specific, typed,
  human-readable errors, distinguishing at minimum: the local service not being
  reachable at the configured address, the requested model not being installed
  locally, a selection too large for the context size (FR-010b), a rejected
  request, a timeout, and an empty response. The first two
  MUST be distinct named error kinds rather than one kind carrying a description,
  and MUST carry the address and the model name respectively, so the message can
  name what the user has to fix.
- **FR-014**: The system MUST classify Ollama failures as retryable or not using
  the existing shared retry rules, so that transient failures receive the
  existing single automatic retry. An unreachable local service and a model that
  is not installed MUST both be classified as permanent and MUST NOT consume the
  automatic retry.
- **FR-015**: The system MUST leave the user's selection unchanged on every
  Ollama failure path, and MUST abort the write if the target context changed
  since the selection was read.
- **FR-016**: The system MUST apply the existing response sanitization to Ollama
  output before writing, so behavior matches other providers.
- **FR-017**: An Ollama run MUST be cancellable by the user and MUST enforce the
  provider's configured time limit, consistent with existing providers.
- **FR-018**: The system MUST NOT contact any address other than the provider's
  configured endpoint when an Ollama action is invoked, and MUST NOT emit
  telemetry. An Ollama run MUST succeed with the machine disconnected from the
  internet.
- **FR-019**: The selected text and the model's output MUST NOT appear in logs
  at the default log level; they MAY appear only under debug logging.
- **FR-020**: The compatibility and privacy documentation MUST be updated to
  record Ollama as an available provider and to state that with an Ollama
  provider the selected text is sent only to the configured endpoint, which is
  the user's own machine in the documented setup.
- **FR-021**: The README MUST document a copy-ready recipe for enabling Ollama:
  a provider block naming the Ollama kind with `llama3.2` as its default model
  and a time limit of 30 seconds, a note that no credential is needed, a note
  that the first run after an idle pause is slower because the model is being
  loaded (with a pointer to the service's own setting for keeping it resident,
  and to the provider time-limit slider for users whose first run times out),
  and the
  prerequisite that the user installs the service and downloads the model
  themselves. It MUST no longer describe Ollama support as forthcoming. The
  shipped default configuration MUST remain unchanged, so a fresh install adds
  no Ollama provider, no keyless provider entry, and no extra global shortcut.

### Key Entities *(include if data involved)*

- **Ollama Provider (configuration record)**: A provider entry whose kind
  identifies it as Ollama. Attributes: identifier, kind, endpoint reference
  (optional, defaulting to the documented local address), default model, time
  limit, retry delay, and an optional Keychain key reference. It carries no
  secret value itself and normally references none.
- **Locally Installed Model**: A model the user has downloaded onto their
  machine through the model service. Overtype reads its name from configuration
  and never installs or removes it.
- **Action (existing)**: An automation record that may name an Ollama provider
  and, optionally, a specific model.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user who already runs the local model service with one model
  installed can enable Ollama and run a successful transformation by choosing the
  provider kind in Settings, or by editing only configuration, entering no
  credential and rebuilding nothing, in under 5 minutes.
- **SC-002**: 100% of Ollama failure cases in the acceptance scenarios (service
  not running, model not installed, selection too large for the context size,
  timeout, empty response) produce a specific human-readable error that names
  the actual cause, and leave the selection unchanged.
- **SC-003**: For a typical short selection with the model already loaded, a
  successful Ollama run completes and writes the result with the same visible
  feedback stages as existing providers, with no perceptible difference in
  interaction.
- **SC-004**: With the machine disconnected from every network interface, an
  Ollama run against a locally installed model completes successfully.
- **SC-005**: Across a full run, the only address contacted is the provider's
  configured endpoint; no other host is reached.
- **SC-006**: In 100% of responses that carry model reasoning alongside the
  answer, only the answer text is written to the user's document. This holds for
  both shapes: reasoning reported in its own field, and reasoning marked inside
  the answer text.
- **SC-007**: Across the full test suite, the selected text and model output
  never appear in any log at the default level, and any stored credential never
  appears in configuration, logs, the request address, or the interface.
- **SC-008**: Adding Ollama required no change to any existing action's
  behavior; all previously configured providers and actions continue to work
  unchanged.

## Assumptions

- The user is responsible for installing the local model service and for
  downloading at least one model before configuring Overtype. Overtype detects
  and reports the absence of either, but never installs, downloads, starts, or
  stops anything on the user's behalf (FR-011). Auto-download was rejected
  because a model is large, the wait is unbounded, and it would begin without the
  user asking, in the middle of a text transformation.
- No credential is required in the normal setup, because the service listens on
  the user's own machine and is not exposed. The optional credential in FR-006
  exists only for users who point the provider at a remote or proxied deployment;
  it is not part of the documented recipe.
- The documented recipe uses `llama3.2` (resolved in Clarifications): a small,
  general-purpose instruction-following model that does not emit reasoning by
  default. Users remain free to configure any installed model, so the reasoning
  filter (FR-009) is still required. Planning confirms the name is still
  distributed by the service and substitutes an equivalent if it is not.
- The action's creativity (temperature) setting IS sent on an Ollama request,
  unlike the Anthropic provider added in feature 007, which omits it. The reason
  for that omission does not apply here: Anthropic's newer models reject the
  field outright with a request error, whereas the local service accepts it
  uniformly as a generation option regardless of which model is loaded.
- The documented recipe uses a 30-second time limit (resolved in
  Clarifications), the same as the cloud recipes. A first request that must load
  a model into memory can legitimately exceed this on slower hardware or with a
  larger model, so the recipe tells the user that raising the provider's time
  limit is the fix. This is a documentation and configuration choice only; no
  new field and no change to the existing time-limit behaviour is introduced.
- Only text-in / text-out transformations are in scope. Multimodal inputs
  (images, documents), tool use, model management (listing, pulling, deleting
  models), and streaming partial output into the document are out of scope.
- The existing run pipeline, feedback HUD, cancellation, timeout, retry,
  sanitization, and Keychain storage are reused as-is; this feature adds Ollama
  as another backend within that pipeline rather than changing the pipeline.
- Ollama is added via the Settings picker and a documented configuration recipe
  rather than pre-seeded in the shipped default config; the default first-run
  configuration is unchanged by this feature, matching how Gemini and Anthropic
  were added.
- A user can already reach a local Ollama service today by configuring an
  OpenAI-compatible provider pointed at the service's compatibility endpoint.
  This feature is still warranted, because that path requires the user to know
  the compatibility endpoint exists, offers no default address, presents a
  credential field that appears mandatory, and produces generic errors for the
  local-only failure modes in User Story 3.
