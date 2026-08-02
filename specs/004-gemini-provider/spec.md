# Feature Specification: Gemini Model Support

**Feature Branch**: `004-gemini-provider`

**Created**: 2026-08-02

**Status**: Completed

**Input**: User description: "let's add support of Gemini models"

## Clarifications

### Session 2026-08-02

- Q: How should Overtype connect to Gemini — a dedicated native Gemini provider, or reuse the OpenAI-compatible provider against Google's OpenAI-compatible endpoint? → A: Dedicated native Gemini provider (new provider kind + provider type calling Google's native Gemini API), so Gemini-specific failures such as safety blocks and empty candidates map to specific typed errors.
- Q: Which Gemini model should be the provider's default model? → A: `gemini-3.5-flash-lite`.
- Q: Should the shipped default configuration pre-seed a Gemini provider, or should enabling Gemini be documentation-only? → A: Documentation-only. The shipped default configuration is unchanged; the README documents how to add a Gemini provider block and store the key. No keyless provider or extra shortcut is added on a fresh install.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run an action against a Gemini model (Priority: P1)

A user who prefers Google's Gemini models configures an Overtype provider that
points at Gemini, stores their Gemini API key in the Keychain, and attaches that
provider to an action (for example "Fix grammar"). They select text in any
supported application, press the action's shortcut, and the selection is
replaced by Gemini's response.

**Why this priority**: This is the core value of the feature. Without the
ability to actually send a selection to Gemini and write the result back,
nothing else matters. It is a complete, demonstrable slice on its own.

**Independent Test**: Configure one Gemini provider and one action that uses it,
select text in a known-supported app, trigger the shortcut, and confirm the
selection is replaced by a Gemini-generated result with the standard
Reading / Thinking / Writing feedback.

**Acceptance Scenarios**:

1. **Given** a Gemini provider is configured with a valid API key and an action
   is bound to it, **When** the user selects text and presses the action's
   shortcut, **Then** the selection is replaced by Gemini's transformed text.
2. **Given** a Gemini action is running, **When** the model is processing,
   **Then** the user sees the standard in-progress feedback (Reading, Thinking,
   Writing) exactly as with existing providers.
3. **Given** the user presses Escape while a Gemini run is in progress,
   **When** the response has not yet been written, **Then** the run is cancelled
   and the original selection is left unchanged.

---

### User Story 2 - Configure Gemini without writing code (Priority: P1)

A user adds Gemini as a provider purely by editing configuration: they declare a
provider record naming Gemini as its kind, a default model, and a Keychain
reference for the key, then store the key. No source-code change or rebuild is
required for them to start using Gemini.

**Why this priority**: The product's core promise is that new AI backends and
automations are added by configuration, not by code. A Gemini provider that
could only be enabled by editing Swift would violate that promise and would not
be usable by end users at all.

**Independent Test**: Starting from a default install, edit only the
configuration file and the Keychain, restart or reload, and confirm a Gemini
action becomes available and works, without touching or rebuilding the
application binary.

**Acceptance Scenarios**:

1. **Given** the configuration declares a provider whose kind is Gemini,
   **When** the configuration is loaded, **Then** the provider is registered and
   selectable by actions.
2. **Given** a Gemini provider references a model, **When** an action using that
   provider runs, **Then** the request targets the action-level model if set,
   otherwise the provider's default model.

---

### User Story 3 - Clear, specific errors for Gemini failures (Priority: P2)

When a Gemini request fails (invalid or missing API key, unknown model, quota
exceeded, network failure, or a safety block on the response), the user sees a
specific, human-readable error and their original selection is untouched.

**Why this priority**: Every run must either succeed or report a specific typed
error, and the original text must survive every failure. Gemini introduces
failure modes (for example a safety-filtered or empty response) that must map to
understandable messages rather than a silent no-op or a corrupted selection.

**Independent Test**: Trigger a Gemini action with a deliberately invalid API
key and confirm a clear authentication error appears and the selection is
unchanged; repeat with an unknown model name.

**Acceptance Scenarios**:

1. **Given** a Gemini provider with an invalid or missing API key, **When** the
   user triggers the action, **Then** a specific authentication error is shown
   and the selection is unchanged.
2. **Given** Gemini returns an empty or safety-blocked response, **When** the
   action runs, **Then** the user sees a specific error explaining no usable
   result was produced and the selection is unchanged.
3. **Given** the network is unavailable, **When** the action runs, **Then** a
   specific network error is shown and the selection is unchanged.

---

### Edge Cases

- What happens when the Gemini API key is absent from the Keychain? The run must
  fail before any text is written, with a message that tells the user a key is
  required.
- How does the system handle a response that Gemini truncates because a token
  limit was reached? The partial result is sanitized and treated like any other
  provider's output; if it is empty, it maps to the "no usable result" error.
- How does the system handle the frontmost app or focused element changing while
  Gemini is still processing? The write is aborted (non-destructive re-check),
  identical to existing providers.
- How does the system present a response that Gemini blocks for safety reasons?
  As a specific typed error, never as a silent success.
- What happens if the configured Gemini model name is not recognized by the
  service? A specific error identifying the model problem is shown and nothing
  is written.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST let a user select Gemini as the backend for an
  action through configuration alone, without any source-code change or rebuild.
- **FR-002**: The system MUST send the action's prompt and the selected text to
  the configured Gemini model and return the model's text response into the
  existing run pipeline (read → call → sanitize → context re-check → write).
- **FR-003**: The system MUST resolve the model for a Gemini run using the
  existing order: the action-level model if present, otherwise the provider's
  `defaultModel`. The documented Gemini provider recipe MUST use
  `gemini-3.5-flash-lite` as its `defaultModel`; the value is supplied entirely
  by the user's configuration, and no code hard-codes a Gemini-specific default.
- **FR-004**: The system MUST read the Gemini API key only from the macOS
  Keychain, referenced by the provider's Keychain key. The key MUST NOT be
  written to configuration, logs, error messages, or the user interface.
- **FR-005**: The system MUST show the same in-progress and success feedback for
  Gemini runs as for existing providers, and MUST NOT take keyboard focus during
  a run.
- **FR-006**: The system MUST report Gemini failures as specific, typed,
  human-readable errors, distinguishing at minimum: missing or invalid
  credentials, unknown or unavailable model, quota or rate limiting, network
  failure, and an empty or safety-blocked response.
- **FR-007**: The system MUST leave the user's selection unchanged on every
  Gemini failure path, and MUST abort the write if the target context changed
  since the selection was read.
- **FR-008**: The system MUST apply the existing response sanitization to Gemini
  output before writing, so behavior matches other providers.
- **FR-009**: A Gemini run MUST be cancellable by the user and MUST enforce a
  hard timeout, consistent with existing providers.
- **FR-010**: The system MUST NOT contact any endpoint other than the Google
  Gemini service when a Gemini action is invoked, and MUST NOT emit telemetry.
- **FR-011**: The selected text and Gemini's output MUST NOT appear in logs at
  the default log level; they MAY appear only under debug logging.
- **FR-012**: The compatibility and privacy documentation MUST be updated to
  record Gemini as an available provider and to state that selected text is sent
  to Google's Gemini endpoint when a Gemini action is used.
- **FR-013**: The README MUST document a copy-ready recipe for enabling Gemini
  (a provider block naming the Gemini kind with default model
  `gemini-3.5-flash-lite`, plus how to store the key in the Keychain). The
  shipped default configuration MUST remain unchanged, so a fresh install adds
  no Gemini provider, no keyless provider entry, and no extra global shortcut.

### Key Entities *(include if data involved)*

- **Gemini Provider (configuration record)**: A provider entry whose kind
  identifies it as Gemini. Attributes: identifier, kind, endpoint/base
  reference, default model, and Keychain key reference. It carries no secret
  value itself.
- **Gemini API Key (secret)**: The user's Google Gemini credential, stored only
  in the macOS Keychain and referenced by the provider record.
- **Action (existing)**: An automation record that may name a Gemini provider
  and, optionally, a specific Gemini model.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can enable Gemini and run a successful transformation by
  editing only configuration and storing one key, without rebuilding the app,
  in under 5 minutes.
- **SC-002**: 100% of Gemini failure cases in the acceptance scenarios (invalid
  key, unknown model, network failure, empty/blocked response) produce a
  specific human-readable error and leave the selection unchanged.
- **SC-003**: For a typical short selection, a successful Gemini run completes
  and writes the result with the same visible feedback stages as existing
  providers, with no perceptible difference in interaction.
- **SC-004**: Across the full test suite, the selected text and model output
  never appear in any log at the default level, and the Gemini API key never
  appears in configuration, logs, or the interface.
- **SC-005**: Adding Gemini required no change to any existing action's behavior;
  all previously configured providers and actions continue to work unchanged.

## Assumptions

- Authentication uses a single Google Gemini API key obtained by the user from
  Google AI Studio, stored in the Keychain like other provider keys. OAuth,
  service accounts, and Vertex AI enterprise authentication are out of scope for
  this feature.
- Only text-in / text-out transformations are in scope. Multimodal inputs
  (images, audio, files) and streaming partial output are out of scope for this
  feature.
- Gemini is reached over the network as a hosted service; local execution is not
  part of this feature.
- The existing run pipeline, feedback HUD, cancellation, timeout, sanitization,
  and Keychain storage are reused as-is; this feature adds Gemini as another
  backend within that pipeline rather than changing the pipeline.
- The in-app Settings provider editor is not required for this feature;
  configuration-file editing plus Keychain storage is a sufficient path to
  enable Gemini, consistent with how providers are added today.
- Gemini is added via a documented configuration recipe rather than pre-seeded
  in the shipped default config; the default first-run configuration is
  unchanged by this feature.

### Revision: Implementation Sync 2026-08-02

- Reason: Reconciled FR-003 with the shipped documentation-only design. The
  default model `gemini-3.5-flash-lite` is a value in the README recipe supplied
  by user configuration, not a system-enforced default; the earlier "MUST be"
  wording implied code enforcement that does not (and by design should not) exist.
