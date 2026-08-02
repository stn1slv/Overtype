# Overtype — Project Specification (Memory)

This is the cumulative, project-level specification, assembled by archiving
merged feature specs into project memory. It follows the section ordering of
`.specify/templates/spec-template.md`. Each block carries a `[Source: …]`
traceability tag naming the feature it came from. New features append here,
continuing the `FR-`, `SC-`, and `US` identifier sequences without renumbering
existing entries.

Governing document: `.specify/memory/constitution.md` (non-negotiable).

Bootstrapped 2026-08-02 from the first archived feature (Gemini Model Support).

---

## User Scenarios

### Gemini Model Support `[Source: specs/004-gemini-provider]`

- **US1 (P1) — Run an action against a Gemini model.** A user configures a
  Gemini provider, stores the key in the Keychain, attaches it to an action,
  selects text, and the selection is replaced by Gemini's response with the
  standard Reading / Thinking / Writing feedback. Escape mid-run cancels and
  leaves the selection unchanged.
- **US2 (P1) — Configure Gemini without writing code.** A user enables Gemini by
  editing configuration and storing a key only; no Swift change or rebuild. A
  `kind: gemini` provider block is registered and selectable by actions; model
  resolution uses the action model if set, else the provider default.
- **US3 (P2) — Clear, specific errors for Gemini failures.** Missing/invalid key,
  unknown model, quota, network failure, and empty/safety-blocked responses each
  produce a specific human-readable error; the original selection is untouched.

### Overtype Foundation `[Source: specs/001-overtype]`

- **US1 (P1) — Grammar correction in chat applications.** A user selects typed
  text in a messaging app and presses a global shortcut; the selection is read
  via Accessibility, sent to the AI service, and the response is typed back in
  place, leaving the clipboard unchanged.
- **US2 (P2) — Adjust tone to formal.** A user rewrites a casual message into a
  formal register via a different configured shortcut, without breaking
  formatting; validates multiple config-defined actions and prompt routing.
- **US3 (P3) — Use a local AI model for privacy.** A privacy-conscious user
  configures an action to run entirely on a local model so text never leaves the
  machine; validates provider extensibility.

### Launch at Login `[Source: specs/002-launch-at-login]`

- **US1 (P1) — Enable launch at login.** A user checks "Launch at Login" in
  settings; the app registers as a macOS login item and starts automatically on
  the next login.
- **US2 (P1) — Disable launch at login.** A user unchecks the box; the app
  deregisters as a login item and no longer starts automatically.

### GUI Configuration Settings `[Source: specs/003-gui-settings]`

- **US1 (P1) — Manage AI providers and credentials.** A user adds/edits/deletes
  OpenAI-compatible providers and enters API keys through a GUI; provider fields
  persist to `config.json` while keys go only to the Keychain; deleting a
  provider also removes its key.
- **US2 (P1) — Manage actions and shortcuts.** A user creates/edits/disables/
  deletes actions and records global hotkeys via an interactive recorder;
  disabling an action immediately unregisters its hotkey.
- **US3 (P2) — Adjust general preferences and typing cadence.** A user toggles
  Launch at Login / Show HUD, adjusts typing speed, and manages per-app typing
  overrides; changes apply immediately without restart.

## Requirements

### Functional Requirements

#### Gemini Model Support `[Source: specs/004-gemini-provider]`

- **FR-001**: Users MUST be able to select Gemini as an action's backend through
  configuration alone, with no source-code change or rebuild.
- **FR-002**: The system MUST send the action prompt and selected text to the
  configured Gemini model and return the response into the existing run pipeline
  (read → call → sanitize → context re-check → write).
- **FR-003**: Model resolution MUST use action-level model if present, else the
  provider `defaultModel`. The documented Gemini recipe uses
  `gemini-3.5-flash-lite`; the value comes from user configuration and no code
  hard-codes a Gemini default.
- **FR-004**: The Gemini API key MUST be read only from the macOS Keychain and
  MUST NOT appear in configuration, logs, error messages, the UI, or the URL.
- **FR-005**: Gemini runs MUST show the same feedback as existing providers and
  MUST NOT take keyboard focus.
- **FR-006**: Gemini failures MUST be specific, typed, human-readable errors,
  distinguishing at minimum: missing/invalid credentials, unknown/unavailable
  model, quota/rate limiting, network failure, and empty/safety-blocked response.
- **FR-007**: The selection MUST be unchanged on every failure path, and the
  write MUST abort if the target context changed since reading.
- **FR-008**: The existing response sanitization MUST be applied to Gemini output
  before writing.
- **FR-009**: A Gemini run MUST be cancellable and MUST enforce a hard timeout.
- **FR-010**: When a Gemini action runs, the system MUST contact only the Google
  Gemini service, with no telemetry.
- **FR-011**: Selected text and Gemini output MUST NOT appear in logs at the
  default level (debug only).
- **FR-012**: Compatibility and privacy docs MUST record Gemini as an available
  provider and its data destination.
- **FR-013**: The README MUST document a copy-ready Gemini enablement recipe, and
  the shipped default configuration MUST remain unchanged (no pre-seeded provider
  or shortcut on a fresh install).

#### Overtype Foundation `[Source: specs/001-overtype]`

IDs renumbered on archival to avoid collision with the entries above; the
original 001 identifier is shown in parentheses.

- **FR-014** (orig FR-001): The system MUST read the user's selected text without
  touching the OS clipboard.
- **FR-015** (orig FR-002): The system MUST replace the selected text in place
  securely and reliably.
- **FR-016** (orig FR-003): The system MUST let users add new text-transformation
  actions via configuration, without code changes.
- **FR-017** (orig FR-004): The system MUST support multiple AI backends
  (cloud-based and local).
- **FR-018** (orig FR-005): The system MUST run as a background menu bar utility
  with no Dock icon or main window.
- **FR-019** (orig FR-006): The system MUST store all authentication keys and
  secrets natively (Keychain).
- **FR-020** (orig FR-007): The system MUST provide HUD visual feedback for
  ongoing tasks that does not steal keyboard focus.
- **FR-021** (orig FR-008): The system MUST sanitize AI responses to strip
  markdown and unnecessary quotes when appropriate.
- **FR-022** (orig FR-009): The system MUST allow users to cancel in-flight AI
  requests seamlessly (e.g., Escape).
- **FR-023** (orig FR-010): The system MUST NOT silently fail; all errors MUST be
  presented to the user clearly.

#### Launch at Login `[Source: specs/002-launch-at-login]`

IDs renumbered on archival to avoid collision; original 002 identifier in
parentheses.

- **FR-024** (orig FR-001): The system MUST provide a "Launch at Login" checkbox
  in the settings UI.
- **FR-025** (orig FR-002): The system MUST register/deregister the app as a
  macOS login item synchronously when the checkbox changes.
- **FR-026** (orig FR-003): The checkbox state MUST reflect the actual OS-level
  login-item state when the settings interface opens.
- **FR-027** (orig FR-004): The system MUST increment the app's minor version
  (v1.X.x → v1.(X+1).0) in project configuration.
- **FR-028** (orig FR-005): On registration/deregistration failure, the system
  MUST notify the user with a human-readable error (Principle VI) and revert the
  checkbox to the true system state.

#### GUI Configuration Settings `[Source: specs/003-gui-settings]`

IDs renumbered on archival to avoid collision; original 003 identifier in
parentheses.

- **FR-029** (orig FR-001): The settings window MUST show three tabs: General,
  Providers, and Actions.
- **FR-030** (orig FR-002): GUI changes MUST auto-save to `config.json`
  immediately (API keys to the Keychain only). Config loads at startup and when
  the settings window becomes active; no live file-system monitoring is required.
- **FR-031** (orig FR-003): The Providers tab MUST let users view/add/modify/
  delete providers (id, kind, base URL, default model, timeout). The provider id
  is an auto-generated read-only slug from the name, with a numeric suffix on
  conflict.
- **FR-032** (orig FR-004): The Actions tab MUST let users view/add/modify/delete
  actions (title, system prompt, temperature, provider, model override, char
  limit, write strategy). The action id is an auto-generated read-only slug from
  the title, numeric suffix on conflict.
- **FR-033** (orig FR-005): The Actions tab MUST include an interactive shortcut
  recorder with conflict detection; on conflict it MUST show an inline warning
  and block saving/registering until resolved.
- **FR-034** (orig FR-006): The General tab MUST configure global typing cadence
  (speed multiplier, chunk size, delay, HUD visibility) and per-application
  overrides (add/remove bundle ids with custom delay/chunk size).

### Key Entities

#### Gemini Model Support `[Source: specs/004-gemini-provider]`

- **Gemini Provider (configuration record)**: A `ProviderConfig` with
  `kind == gemini`. Fields: `id`, `kind`, optional `baseURL` (defaults to
  `https://generativelanguage.googleapis.com/v1beta/`), `defaultModel`,
  `timeoutSeconds`, `keychainKey`. Holds no secret value.
- **Gemini API Key (secret)**: The user's Google Gemini credential, stored only
  in the macOS Keychain, referenced by `keychainKey`.
- **Action (existing)**: May name a Gemini provider and optionally a model.

#### Overtype Foundation `[Source: specs/001-overtype]`

- **Action Configuration**: Defines an automation (prompt, shortcut, provider,
  behavior). The base entity that a Gemini action specializes.
- **Provider Configuration**: Defines an AI backend (URL/base, model, timeout,
  Keychain key). The base entity; the Gemini provider is a `kind` of this.
- **Global Settings**: Application settings (typing speed, HUD visibility).

#### GUI Configuration Settings `[Source: specs/003-gui-settings]`

No new entities — the GUI edits the existing base entities. Concrete
`Codable` struct names in code: `GeneralConfig` (= Global Settings),
`ProviderConfig` (= Provider Configuration), `ActionConfig` (= Action
Configuration), and the Keychain Secret bound to a `ProviderConfig.keychainKey`.

### Edge Cases and Error Handling

#### Gemini Model Support `[Source: specs/004-gemini-provider]`

- Absent Keychain key → fail before any write with a "key required" message.
- Truncated (token-limit) response → sanitized like any output; empty → "no
  usable result" error.
- Frontmost app / focused element changes mid-run → write aborted
  (non-destructive re-check).
- Safety-blocked response → specific typed error, never a silent success.
- Unrecognized model name → specific error identifying the model problem.

#### Overtype Foundation `[Source: specs/001-overtype]`

- Target app loses focus while a request is in flight → the write is aborted to
  avoid replacing text in the wrong window.
- Selecting text in an unsupported app (e.g., terminal emulator) → a clear
  "unsupported" error, not a silent failure.
- User is physically holding modifier keys when replacement starts → the app
  waits for physical modifier release before typing.
- AI wraps output in quotation marks the original lacked → the response sanitizer
  strips them.

#### Launch at Login `[Source: specs/002-launch-at-login]`

- User removes the app from Login Items via macOS System Settings (not the app
  UI) → the app UI must reflect the true system state when reopened.
- App moved to a different directory → native APIs generally handle this.
- Registration fails due to permissions/other errors → surface a human-readable
  error and revert the checkbox.

#### GUI Configuration Settings `[Source: specs/003-gui-settings]`

- Shortcut recorded with no modifier (e.g. bare "A") → the recorder blocks it to
  avoid hijacking normal typing.
- Action saved with an empty system/user prompt → inline validation error.
- Action invoked for a provider with no stored key → human-readable HUD error
  pointing to settings.
- Malformed `config.json` → app falls back to defaults gracefully; the settings
  window offers to reset to defaults.

## Success Criteria

#### Gemini Model Support `[Source: specs/004-gemini-provider]`

- **SC-001**: A user can enable Gemini and run a successful transformation by
  editing only configuration and storing one key, without rebuilding, in under
  5 minutes.
- **SC-002**: 100% of the acceptance failure cases (invalid key, unknown model,
  network failure, empty/blocked response) produce a specific error and leave the
  selection unchanged.
- **SC-003**: A successful Gemini run shows the same feedback stages as existing
  providers, with no perceptible interaction difference.
- **SC-004**: Across the test suite, selected text and model output never appear
  in logs at the default level, and the Gemini key never appears in config, logs,
  or the UI.
- **SC-005**: Adding Gemini changed no existing action's behavior; all previously
  configured providers and actions continue to work unchanged.

#### Overtype Foundation `[Source: specs/001-overtype]`

IDs renumbered on archival to avoid collision; original 001 identifier in
parentheses.

- **SC-006** (orig SC-001): The user's system clipboard is verifiably unchanged
  after executing any action.
- **SC-007** (orig SC-002): Text replacement completes smoothly and reliably
  across native and web-based desktop applications.
- **SC-008** (orig SC-003): Users can add new AI providers and custom actions
  dynamically via configuration without restarting.
- **SC-009** (orig SC-004): No user text, AI output, or secrets are logged
  persistently unless explicitly opted in for diagnostics.
- **SC-010** (orig SC-005): Failures are handled gracefully, leaving the original
  selected text fully intact on any error.

#### Launch at Login `[Source: specs/002-launch-at-login]`

IDs renumbered on archival to avoid collision; original 002 identifier in
parentheses.

- **SC-011** (orig SC-001): Users can enable the setting and verify the app
  starts automatically on a subsequent login.
- **SC-012** (orig SC-002): Users can disable the setting and verify the app no
  longer starts automatically.
- **SC-013** (orig SC-003): 100% of the time, the Settings UI reflects the
  system's actual login-item state.
- **SC-014** (orig SC-004): The app version is visibly incremented in the build
  output / application bundle.

#### GUI Configuration Settings `[Source: specs/003-gui-settings]`

IDs renumbered on archival to avoid collision; original 003 identifier in
parentheses.

- **SC-015** (orig SC-001): A user can add a new automation, configure prompts,
  and assign a hotkey in under 45 seconds using only the GUI.
- **SC-016** (orig SC-002): 100% of API keys configured via the GUI are stored
  only in the Keychain, never in `config.json` or diagnostic logs.
- **SC-017** (orig SC-003): 100% of configuration changes via the settings UI
  take effect immediately without a restart.
- **SC-018** (orig SC-004): A hotkey conflict during recording is flagged
  immediately and duplicate registration is prevented.

---

### Revision: Archival 2026-08-02

- Reason: Archived the foundational feature `specs/001-overtype` into project
  memory (out of chronological order, after 004). Its FR/SC IDs were renumbered
  to FR-014–FR-023 and SC-006–SC-010 to avoid collision with the entries already
  archived from 004; original 001 IDs are annotated inline. User stories, base
  entities, and edge cases were merged as a `[Source: specs/001-overtype]`
  sub-block under each section.

### Revision: Archival 2026-08-02 (Launch at Login)

- Reason: Archived `specs/002-launch-at-login`. IDs renumbered to FR-024–FR-028
  and SC-011–SC-014 to continue the sequence; original 002 IDs annotated inline.
  No Key Entities (the feature adds no data model). Merged as
  `[Source: specs/002-launch-at-login]` sub-blocks.

### Revision: Archival 2026-08-02 (GUI Configuration Settings)

- Reason: Archived `specs/003-gui-settings`. IDs renumbered to FR-029–FR-034 and
  SC-015–SC-018; original 003 IDs annotated inline. No new entities — the feature
  operates on the existing `GeneralConfig` / `ProviderConfig` / `ActionConfig`
  entities (referenced, not duplicated). Merged as `[Source: specs/003-gui-settings]`
  sub-blocks. With this run, the project's four features (001, 002, 003, 004) are
  all archived.
