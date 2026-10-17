# Overtype — Project Specification (Memory)

> **Revision**: 2026-10-17 · Archived `specs/010-model-aware-parameters` (model-aware temperature and reasoning effort). New entries under topic sub-blocks "Model-Aware Generation Parameters" with item-level refs: US1 to US4, FR-041 to FR-068, SC-024 to SC-029, AS-006 to AS-014, entities "Model profile" and "Learned rejection", nine edge cases. The feature's "Action override" entity folded into the existing "Action Configuration" entity. Existing unnumbered assumptions backfilled as AS-001 to AS-005 (labels only). No supersessions.

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

### Reliable Selection Reading (Dormant Accessibility Trees) `[Source: specs/005-teams-ax-recovery/spec.md]`

- **US1 (P1) — Fix text in an app whose accessibility tree is dormant.** After
  Microsoft Teams restarts (or updates, or the Mac reboots), a user selects text
  and invokes an action. Instead of failing instantly with "Cannot find the
  focused text element" until an external assistive tool touches the app,
  Overtype detects the dormant tree, wakes it, retries briefly, and completes
  the transformation.
- **US2 (P2) — No regression for well-behaved apps.** In apps whose accessibility
  support works immediately (native apps, Outlook, warmed-up Teams), latency and
  behavior are unchanged and no wake-up flags are set on the target application.
- **US3 (P3) — Failures still fail fast and clearly.** With nothing selected, or
  in a genuinely unsupported app, the run ends with the same specific error as
  before, after a bounded retry window; Escape during that window cancels
  immediately.

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

### Model-Aware Generation Parameters

- **US1 (P1): Current models work with no extra setup.** A user changes the model of the "Fix grammar" action to `gpt-6-luna`. Before this feature every run failed with "API Error 400: Unsupported value: 'temperature' does not support 0 with this model". Now the run succeeds without the user changing any other setting, because Overtype knows how to talk to that model. The same holds for current Claude and Gemini models. The user does not need to know what temperature, reasoning effort or thinking level mean. `[Source: specs/010-model-aware-parameters/spec.md -> User Story 1]`
  - *Why this priority*: This is the reported defect, and the user's explicit requirement is that model details are the project's responsibility.
  - *Independent Test*: Take an existing configuration whose action stores temperature 0, change only the model to `gpt-6-luna`, run the action in a supported app, and confirm the selection is replaced with no error. Repeat with a profiled Claude model and a profiled Gemini 3.x model.
  - *Acceptance Scenarios*: (1) Given an action that stores temperature 0 and uses `gpt-6-luna`, when the user runs it, then the selection is replaced on the first request, with no error. (2) Given an action on a model that has a built-in profile, when the user runs it with both settings on "Automatic", then the request uses the profile's settings for that model. (3) Given an action that stores temperature 0 and uses a Gemini model whose profile says to remove temperature, when the user runs it, then the request carries no temperature. (4) Given an action on a model with no built-in profile that works today, on any provider, when the user runs it after upgrading, then the request is identical to the request sent before the upgrade.
- **US2 (P1): New users start on a current OpenAI model.** A user installs Overtype for the first time, or adds a new OpenAI provider in Settings. The provider's default model is `gpt-6-luna` unless the user types a different one. A user who already has a provider configured keeps their model. `[Source: specs/010-model-aware-parameters/spec.md -> User Story 2]`
  - *Why this priority*: The first experience should use a current model that Overtype knows how to call, and the user asked for this default.
  - *Independent Test*: Start with no configuration file, launch Overtype, and confirm the seeded OpenAI provider's default model is `gpt-6-luna` and "Fix grammar" works. Then add a new OpenAI provider in Settings and confirm the model field is pre-filled with `gpt-6-luna`.
  - *Acceptance Scenarios*: (1) Given no configuration file exists, when Overtype launches, then the seeded OpenAI provider's default model is `gpt-6-luna` and the seeded action uses "Automatic" for both settings. (2) Given the user adds a new provider of the OpenAI kind in Settings, when the editor opens, then the default model field contains `gpt-6-luna`, and the user can replace it. (3) Given an existing configuration with any OpenAI default model, when Overtype is upgraded, then that model is not changed.
- **US3 (P1): Unknown OpenAI models adapt instead of failing.** A new OpenAI model is released after the current Overtype version, or the user points the OpenAI-compatible provider at another service. The model rejects a parameter Overtype sends. Instead of showing an error, Overtype retries once without that parameter, the run succeeds, and later runs with that model in the same session skip the parameter from the start. `[Source: specs/010-model-aware-parameters/spec.md -> User Story 3]`
  - *Why this priority*: OpenAI profiles always lag behind new models, and for OpenAI a stale profile or a stored temperature turns into a 400 error.
  - *Independent Test*: Use an OpenAI model with no profile that rejects `temperature` (or simulate one in a unit test), run the action, and confirm the run succeeds after one extra request; run it again and confirm only one request is sent.
  - *Acceptance Scenarios*: (1) Given an OpenAI model with no profile that rejects a parameter Overtype sent and the structured error names it, when the user runs the action, then Overtype retries once without that parameter and the selection is replaced. (2) Given that a parameter was learned as rejected for a model during this session, when the user runs an action on the same provider and model again, then the first request does not contain that parameter. (3) Given the provider rejects the request with a 400 error that does not name a parameter Overtype can drop, when the user runs the action, then no adaptive retry happens and the existing typed error is shown. (4) Given an adaptive retry is in progress, when the user presses Escape, then the run is cancelled and the selection is unchanged.
- **US4 (P2): Advanced users can override the automatic choice.** An advanced user wants more careful rewrites from a "Rewrite formally" action and sets its reasoning effort to `high`. Another user sets a specific temperature. The editor shows "Automatic" by default, offers the values that the action's provider understands, and shows what "Automatic" means for the current model when it has a profile. `[Source: specs/010-model-aware-parameters/spec.md -> User Story 4]`
  - *Why this priority*: The automatic behavior covers the common case. The override is an escape hatch for specific needs and for a profile that turns out to be wrong.
  - *Independent Test*: In Settings, set an action's reasoning effort to `high`, save, run it, and confirm the request carries `high` in the provider's own parameter; set it back to "Automatic" and confirm the profile's value is used again.
  - *Acceptance Scenarios*: (1) Given the action editor is open, when the user leaves both settings on "Automatic" and saves, then the action is stored without either value. (2) Given the user sets a reasoning effort or a temperature and saves, when the action runs, then the user's value is used instead of the profile's preference, unless the profile says the model does not accept it. (3) Given the selected model has a profile, when the editor shows the "Automatic" option, then it also shows what Automatic resolves to for that model (for example "Automatic (none)"). (4) Given a hand-edited reasoning effort that the editor does not list, when the user opens and saves the action without touching that field, then the value is kept unchanged.

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
- **FR-022** (orig FR-009): The system MUST allow users to cancel in-flight runs
  seamlessly (e.g., Escape). This includes cancellation during the dormant-tree
  recovery window (FR-035), which MUST end the run promptly with no modification
  to the target document.
  `[Source: specs/001-overtype/spec.md -> FR-009; specs/005-teams-ax-recovery/spec.md -> FR-006]`
- **FR-023** (orig FR-010): The system MUST NOT silently fail; all errors MUST be
  presented to the user clearly. Exhausting the dormant-tree recovery window
  (FR-035) MUST end the run with the same specific, typed errors as a
  single-shot lookup failure — no new silent failure modes and no indefinite
  waiting.
  `[Source: specs/001-overtype/spec.md -> FR-010; specs/005-teams-ax-recovery/spec.md -> FR-007]`

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

#### Reliable Selection Reading (Dormant Accessibility Trees) `[Source: specs/005-teams-ax-recovery/spec.md]`

IDs renumbered on archival to avoid collision; original 005 identifier in
parentheses. Cancellation (orig FR-006) and the unchanged error surface (orig
FR-007) were consolidated into FR-022 and FR-023 rather than restated here.

- **FR-035** (orig FR-001): When the existing focused-element lookup strategies
  find no element with a live selection, the system MUST attempt a bounded
  recovery instead of failing immediately.
- **FR-036** (orig FR-002): The recovery MUST wake the target application's
  accessibility support by setting the two known assistive-client flags on the
  target application, and MUST ignore the reported result codes of those calls,
  because at least one target application (Microsoft Teams) reports an error
  while honoring the call. This site MUST carry an inline comment naming the
  quirk (Principle III).
- **FR-037** (orig FR-003): The recovery MUST retry the focused-element lookup,
  querying the application element first, up to 24 attempts at 150 ms intervals.
  Ordering and interval come from the 2026-07-31 axprobe findings (binding
  conclusion #3); the attempt count was raised from that report's 12 after the
  2026-08-02 acceptance run showed a truly cold Teams populates the selection
  attribute only about 2.7 seconds after the wake.
- **FR-038** (orig FR-004): The recovery MUST apply a bounded messaging timeout
  (2 seconds) to accessibility queries issued during the recovery, so a hung
  target application cannot stall a run beyond the hard timeout.
- **FR-039** (orig FR-005): The fast path MUST remain unchanged: if the existing
  strategies find the selection, no flags are set, no retries occur, and no
  latency is added.
- **FR-040** (orig FR-008): The empirical basis and the per-application outcome
  MUST be recorded in `docs/compatibility.md` (Teams dormant-tree behavior, the
  wake-up quirk, and the re-verified acceptance results).

#### Model-Aware Generation Parameters

IDs renumbered on archival to avoid collision; each entry's source ref names the original 010 identifier.

- **FR-041**: Overtype MUST ship built-in model profiles for the OpenAI-compatible, Anthropic and Gemini providers. A profile records, per model: the provider's reasoning parameter and the values the model supports, whether the model accepts a temperature (and under which reasoning value), and the reasoning value Overtype prefers. Overtype prefers the lowest latency that the model supports, because it rewrites text while the user waits. `[Source: specs/010-model-aware-parameters/spec.md -> FR-001]`
- **FR-042**: The reasoning parameter is provider-native: `reasoning_effort` for OpenAI, `output_config.effort` for Anthropic, and for Gemini either `thinkingLevel` or `thinkingBudget`, as the model's profile records. Overtype MUST NOT send both Gemini parameters in one request. `[Source: specs/010-model-aware-parameters/spec.md -> FR-002]`
- **FR-043**: The initial profiles MUST cover at least: the OpenAI GPT-6 family (`gpt-6-luna`, `gpt-6-sol`, `gpt-6-astra`, `gpt-6.1-sol`); the Claude models listed in Anthropic's effort documentation; the current Gemini 3.x and 4 text models and the Gemini 2.5 text models; and every model named in Overtype's seeded configuration and documentation recipes for providers that have profiles (OpenAI-compatible, Anthropic, Gemini; Ollama recipes are exempt under FR-045). Deliberately excluded: `gemini-2.5-flash-lite` (it does not think by default, so a profile would change nothing) and Gemini preview models other than `gemini-3-flash-preview` and `gemini-3.1-pro-preview`. Each profile MUST record the documentation source and date it is based on, and model IDs MUST be checked against the providers' deprecation pages. `[Source: specs/010-model-aware-parameters/spec.md -> FR-003]`
- **FR-044**: A model MUST match a profile when its ID equals the profile's model ID or is a dated snapshot of it. `[Source: specs/010-model-aware-parameters/spec.md -> FR-004]`
- **FR-045**: Profiles MUST be part of Overtype itself, updated with releases. The end user MUST NOT need to edit them or know they exist. Ollama has no profiles: Ollama applies generation options itself, and its models are the user's own. `[Source: specs/010-model-aware-parameters/spec.md -> FR-005]`
- **FR-046**: The effective reasoning value MUST be the action's override if set, otherwise the profile's preferred value if the model has a profile, otherwise none (no reasoning parameter sent). `[Source: specs/010-model-aware-parameters/spec.md -> FR-006]`
- **FR-047**: The effective temperature MUST be the action's override if set, otherwise none (the model's own default). `[Source: specs/010-model-aware-parameters/spec.md -> FR-007]`
- **FR-048**: A value MUST NOT be sent when the model's profile says the model rejects it or the provider's documentation tells clients to remove it, even when the action sets it. This covers a temperature at a reasoning value that excludes it (OpenAI), any temperature on Gemini 3.x and 4, and a reasoning value the model does not support. `[Source: specs/010-model-aware-parameters/spec.md -> FR-008]`
- **FR-049**: For a model without a profile, Overtype MUST send exactly the parameters the action sets and nothing else, so every model that works today gets the same request as before. `[Source: specs/010-model-aware-parameters/spec.md -> FR-009]`
- **FR-050**: Anthropic MUST keep omitting temperature in all cases (feature 007). Ollama MUST NOT receive a reasoning value, and MUST receive a temperature only when the action sets one. `[Source: specs/010-model-aware-parameters/spec.md -> FR-010]`
- **FR-051**: When the OpenAI-compatible provider rejects a request with HTTP 400 and the structured error identifies a parameter that Overtype sent and is allowed to drop (`temperature` or `reasoning_effort`), Overtype MUST retry once without that parameter, but only when the value it sent was a plausible one: a temperature from 0.0 to 2.0, or a reasoning level from the OpenAI value list in FR-062. A rejection of any other value, such as a typo, surfaces as the existing API error. `[Source: specs/010-model-aware-parameters/spec.md -> FR-011]`
- **FR-052**: Overtype MUST remember a dropped parameter together with the value that was rejected, for that provider, base URL and model, for the rest of the app session, and MUST NOT send that same value in later runs; a different value for the parameter is sent again. `[Source: specs/010-model-aware-parameters/spec.md -> FR-012]`
- **FR-053**: The adaptive fallback MUST NOT apply to any other error, MUST be cancellable, MUST show the existing retry feedback, and MUST NOT change the existing transient retry rules. `[Source: specs/010-model-aware-parameters/spec.md -> FR-013]`
- **FR-054**: Before the fallback is relied on, a recorded diagnostic run MUST confirm that OpenAI's structured error names the rejected parameter for both `temperature` and `reasoning_effort` (Principle III). `[Source: specs/010-model-aware-parameters/spec.md -> FR-014]`
- **FR-055**: The fallback MUST NOT apply to Anthropic or Gemini. `[Source: specs/010-model-aware-parameters/spec.md -> FR-015]`
- **FR-056**: Overtype MUST identify a rejected parameter from a structured error field only, never by matching error message text. A dropped parameter MAY be logged by parameter name, provider id and model; the error message, which can echo submitted text, MUST NOT be logged at `info` level or above. `[Source: specs/010-model-aware-parameters/spec.md -> FR-016]`
- **FR-057**: The seeded configuration MUST use `gpt-6-luna` as the OpenAI provider's default model, and its seeded action MUST use "Automatic" for both settings. `[Source: specs/010-model-aware-parameters/spec.md -> FR-017]`
- **FR-058**: When the user adds a new provider of the OpenAI kind in Settings, the default model field MUST be pre-filled with `gpt-6-luna`, and the user MUST be able to replace it. `[Source: specs/010-model-aware-parameters/spec.md -> FR-018]`
- **FR-059**: An existing provider's default model and an action's model MUST NOT be changed by an upgrade. A unit test MUST show that loading an existing configuration never replaces its providers' `defaultModel` with the seeded value. `[Source: specs/010-model-aware-parameters/spec.md -> FR-019]`
- **FR-060**: An action's temperature and reasoning effort MUST both be optional; absent means "Automatic". Saving "Automatic" MUST leave the key out of the configuration file. `[Source: specs/010-model-aware-parameters/spec.md -> FR-020]`
- **FR-061**: Configuration files written before this feature MUST load without loss; a stored temperature becomes the action's override and is kept in the file (FR-048 can still prevent it from being sent). `[Source: specs/010-model-aware-parameters/spec.md -> FR-021]`
- **FR-062**: The action editor MUST offer "Automatic" or a specific temperature (0.0 to 2.0). For reasoning effort, it MUST offer "Automatic" or one of the values of the action's provider kind: OpenAI `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`; Anthropic `low`, `medium`, `high`, `xhigh`, `max`; Gemini `minimal`, `low`, `medium`, `high`. The value is passed to the provider unchanged. The editor MUST keep and display a hand-edited value that is not in the list, and MUST NOT offer reasoning effort for Ollama. `[Source: specs/010-model-aware-parameters/spec.md -> FR-022]`
- **FR-063**: When the selected model has a profile, the editor MUST show what "Automatic" resolves to, and MUST warn when an override will not be sent under FR-048. `[Source: specs/010-model-aware-parameters/spec.md -> FR-023]`
- **FR-064**: New actions MUST default to "Automatic" for both settings. `[Source: specs/010-model-aware-parameters/spec.md -> FR-024]`
- **FR-065**: Profile lookup, effective-parameter resolution, request-body construction for every provider, and the decision whether an error allows an adaptive retry MUST be pure logic covered by unit tests. `[Source: specs/010-model-aware-parameters/spec.md -> FR-025]`
- **FR-066**: The reason for each omitted or dropped parameter MUST be recorded in the code where it happens, so the behavior is not "simplified" later. `[Source: specs/010-model-aware-parameters/spec.md -> FR-026]`
- **FR-067**: User-facing documentation MUST describe "Automatic", the override, the new OpenAI default model, and that Overtype adapts to OpenAI models it does not know. Documentation recipes for providers that have profiles MUST use models that have profiles and are not deprecated; the Ollama recipe is exempt (FR-045). `[Source: specs/010-model-aware-parameters/spec.md -> FR-027]`
- **FR-068**: When a run does not send an override that the action sets, Overtype MUST log it at `warning` level, naming the parameter, the reason and the model, never the value (Principle VI). `[Source: specs/010-model-aware-parameters/spec.md -> FR-028]`

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
  behavior). The base entity that a Gemini action specializes. Carries an
  optional temperature (0.0 to 2.0) and an optional reasoning effort
  (provider-native text) as overrides; absent means "Automatic".
  `[Source: specs/010-model-aware-parameters/spec.md -> "Action override"]`
- **Provider Configuration**: Defines an AI backend (URL/base, model, timeout,
  Keychain key). The base entity; the Gemini provider is a `kind` of this.
- **Global Settings**: Application settings (typing speed, HUD visibility).

#### GUI Configuration Settings `[Source: specs/003-gui-settings]`

No new entities — the GUI edits the existing base entities. Concrete
`Codable` struct names in code: `GeneralConfig` (= Global Settings),
`ProviderConfig` (= Provider Configuration), `ActionConfig` (= Action
Configuration), and the Keychain Secret bound to a `ProviderConfig.keychainKey`.

#### Reliable Selection Reading (Dormant Accessibility Trees) `[Source: specs/005-teams-ax-recovery/spec.md]`

No persistent entities, configuration schema, or stored state. Two runtime-only
concepts, both function-local to the selection read:

- **Recovery attempt**: a bounded sequence (wake flags once, then up to 24
  lookup retries at 150 ms) executed at most once per run.
- **Wake-up flags**: the two assistive-client attributes that signal "an
  assistive client is present" to the target application —
  `AXEnhancedUserInterface` (honored by Teams-like apps despite the reported
  error) and `AXManualAccessibility` (honored by Electron apps).

#### Model-Aware Generation Parameters

- **Model profile**: Overtype's built-in knowledge about one model of one provider: the reasoning parameter and supported values, the temperature rule, the preferred reasoning value, and the documentation source and date. `[Source: specs/010-model-aware-parameters/spec.md -> "Model profile"]`
- **Learned rejection**: a parameter, and the value of it, that a specific OpenAI-compatible provider, base URL and model rejected during the current app session. Only that value is withheld later. It is held in memory only. `[Source: specs/010-model-aware-parameters/spec.md -> "Learned rejection"]`

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

- Target app loses focus, or quits, while a request is in flight → the write is
  aborted to avoid replacing text in the wrong window. This holds equally when
  the app quits or loses frontmost status during the dormant-tree recovery
  window; the existing pre-write context re-check still applies.
  `[Source: specs/001-overtype/spec.md; specs/005-teams-ax-recovery/spec.md]`
- Selecting text in an unsupported app (e.g., terminal emulator) → a clear
  "unsupported" error, not a silent failure. An app that never exposes a
  selection ends the bounded retry window in that same specific error; it is not
  retried indefinitely.
  `[Source: specs/001-overtype/spec.md; specs/005-teams-ax-recovery/spec.md]`
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

#### Reliable Selection Reading (Dormant Accessibility Trees) `[Source: specs/005-teams-ax-recovery/spec.md]`

- The wake-up call reports an error even when it works → the reported error code
  must not be treated as failure evidence (verified quirk; Principle III).
- Repeated invocations while a retry window is active → the existing
  cancel-previous-run behavior applies unchanged.

#### Model-Aware Generation Parameters

- The user's override conflicts with a documented limit in the model's profile (a temperature the model rejects or the provider says to remove, or a reasoning effort the model does not support): the value is not sent, and the editor tells the user that it does not apply to this model. `[Source: specs/010-model-aware-parameters/spec.md -> "The user's override conflicts with a documented limit"]`
- The user's override is rejected by an OpenAI model without a profile: the adaptive fallback applies, because the alternative is a guaranteed failure. On Anthropic or Gemini, the provider's error is shown, as before. `[Source: specs/010-model-aware-parameters/spec.md -> "The user's override is rejected by an OpenAI model without a profile"]`
- A model ID is a dated snapshot of a profiled model (for example `gpt-6-luna-2026-09-01`): it uses the same profile. `[Source: specs/010-model-aware-parameters/spec.md -> "A model ID is a dated snapshot of a profiled model"]`
- A profiled model is deprecated and silently routed by the provider to its successor (for example `gemini-3.5-flash`): the profile describes the model that actually answers. `[Source: specs/010-model-aware-parameters/spec.md -> "A profiled model is deprecated and silently routed"]`
- Two different parameters are rejected one after the other in the same OpenAI run: each is dropped once, so one run sends at most one adaptive retry per droppable parameter. `[Source: specs/010-model-aware-parameters/spec.md -> "Two different parameters are rejected"]`
- The adaptive retry also fails for a transient reason (timeout, 5xx): the existing single transient retry rules apply unchanged; the two retry kinds do not combine into an unbounded loop. `[Source: specs/010-model-aware-parameters/spec.md -> "The adaptive retry also fails for a transient reason"]`
- A hand-edited action has no `temperature` key, a `null` value, or a wrong-typed value: it is treated as "Automatic"; a wrong type is reported in the existing launch warning by key and action id, never by value. The same applies to `reasoningEffort`, where an empty or whitespace-only value also means "Automatic". `[Source: specs/010-model-aware-parameters/spec.md -> "A hand-edited action has no temperature key"]`
- The action's provider kind changes after a reasoning effort was set: when the new kind takes no reasoning setting (Ollama), the editor hides the control and does not save the value, so nothing invisible is stored; when the new kind has its own value list and does not understand the value, the value is kept, the editor warns, and a profiled model does not receive it. `[Source: specs/010-model-aware-parameters/spec.md -> "The action's provider kind changes after a reasoning effort was set"]`
- The user changes the provider's model or base URL: rules learned for the old provider and model do not apply to the new one. `[Source: specs/010-model-aware-parameters/spec.md -> "The user changes the provider's model or base URL"]`

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

#### Reliable Selection Reading (Dormant Accessibility Trees) `[Source: specs/005-teams-ax-recovery/spec.md]`

IDs renumbered on archival to avoid collision; original 005 identifier in
parentheses.

- **SC-019** (orig SC-001): After restarting Microsoft Teams, the first Overtype
  run against a Teams selection succeeds without any external warm-up, in at
  most 3 seconds more than a warm run.
- **SC-020** (orig SC-002): Runs against applications that already work (Outlook,
  native apps, warmed Teams) show no measurable latency increase (within normal
  variance) and no behavioral change.
- **SC-021** (orig SC-003): With nothing selected, the failure message is
  unchanged; in apps with an awake tree it stays instant, and in the cold-tree
  case the added delay stays within the bounded recovery window (about four
  seconds).
- **SC-022** (orig SC-004): Escape pressed during the recovery window cancels the
  run in under one second, with the target document untouched.
- **SC-023** (orig SC-005): The recorded manual acceptance for Teams in
  `docs/compatibility.md` passes from a cold Teams restart, twice in a row.

#### Model-Aware Generation Parameters

- **SC-024**: A configuration that worked before this feature, with only the model changed to `gpt-6-luna`, runs successfully on the first request, with no change to any other setting. `[Source: specs/010-model-aware-parameters/spec.md -> SC-001]`
- **SC-025**: A fresh install runs the seeded "Fix grammar" action against `gpt-6-luna` successfully with only an API key added. `[Source: specs/010-model-aware-parameters/spec.md -> SC-002]`
- **SC-026**: For an OpenAI model with no profile that rejects `temperature`, the first run succeeds with exactly one extra request, and every later run in the same session sends exactly one request. `[Source: specs/010-model-aware-parameters/spec.md -> SC-003]`
- **SC-027**: For models without a profile, on every provider, 100% of the requests built after the upgrade for actions that store a temperature value are identical to the requests built before it. `[Source: specs/010-model-aware-parameters/spec.md -> SC-004]`
- **SC-028**: A run with both settings on "Automatic" succeeds on the first request for one model of each profile shape: `gpt-6-luna` (OpenAI with `none`), `gpt-6.1-sol` (OpenAI without `none`), `claude-haiku-5-5` (Anthropic), `gemini-3.5-flash-lite` (Gemini level, prefers `minimal`), `gemini-3.8-flash` (Gemini level, prefers `low`) and `gemini-2.5-flash` (Gemini budget). For each provider, on one representative profiled model, the median time of five "Automatic" runs on the same text is lower than the median of five runs at the provider's default reasoning level. `[Source: specs/010-model-aware-parameters/spec.md -> SC-005]`
- **SC-029**: Requests to Ollama never contain a reasoning value, and requests to Anthropic never contain a temperature, in 100% of unit-tested cases. `[Source: specs/010-model-aware-parameters/spec.md -> SC-006]`

## Assumptions

Recorded per feature; only assumptions that still govern the implemented system
are kept.

#### Reliable Selection Reading (Dormant Accessibility Trees) `[Source: specs/005-teams-ax-recovery/spec.md]`

- **AS-001**: Teams' accessibility tree is dormant after a process restart, and setting the
  assistive-client flag wakes it even though the call reports an error
  (2026-08-02 diagnosis; re-verified by the manual acceptance procedure).
- **AS-002**: The retry configuration (24 x 150 ms, app-element first) is sufficient for the
  Teams and VS Code class of applications; no per-app tuning is provided. VS
  Code's recorded 13-second outlier is out of reach by design — a second press
  covers it.
- **AS-003**: Setting the wake-up flags only on the failure path is an acceptable trade-off
  for avoiding known side effects (window-resize glitches in some Electron apps)
  on apps that do not need them.
- **AS-004**: No configuration surface is added: the recovery is automatic and invisible;
  constants live in code, matching the tested values.
- **AS-005**: Writing (typing) behavior is out of scope for this recovery; it changes only
  how the selection is found and read.

#### Model-Aware Generation Parameters

- **AS-006**: The OpenAI Models API reports no parameter support. Anthropic's and Gemini's report only part of what Overtype needs. Profiles are therefore built in for all three. `[Source: specs/010-model-aware-parameters/spec.md -> "The OpenAI Models API reports no parameter support"]`
- **AS-007**: Learned rejections are kept in memory only. One extra request per OpenAI model after each app launch is an acceptable cost, and a wrong learned rule cannot persist. `[Source: specs/010-model-aware-parameters/spec.md -> "Learned rejections are kept in memory only"]`
- **AS-008**: Profiles match by model ID, whatever the provider's base URL is. A compatible service that uses a different ID for the same model gets no profile. `[Source: specs/010-model-aware-parameters/spec.md -> "Profiles match by model ID"]`
- **AS-009**: Part of the `gpt-6-luna` profile is inferred, not stated: OpenAI says to remove `temperature` "when reasoning effort is not `none`", which implies that `gpt-6-luna` accepts it at `none`. The SC-024 acceptance run confirms this; if it is wrong, the profile is corrected, and the fallback keeps runs working meanwhile. Every profile's content is treated as a claim to verify, as in FR-054. `[Source: specs/010-model-aware-parameters/spec.md -> "Part of the gpt-6-luna profile is inferred"]`
- **AS-010**: The meaning of a missing `temperature` key changed from 0.0 to "Automatic". The app and the previous seeded configuration always wrote the key, so only hand-written configurations without it are affected. `[Source: specs/010-model-aware-parameters/spec.md -> "The meaning of a missing temperature key changes"]`
- **AS-011**: Profiles change requests for existing, working Anthropic and Gemini configurations on profiled models (a lower reasoning level, and no temperature on Gemini 3.x and 4). This is the intended effect of "the project knows"; SC-027 covers only models without a profile. `[Source: specs/010-model-aware-parameters/spec.md -> "Profiles change requests for existing"]`
- **AS-012**: Overtype sends no `top_p`, `top_k`, `top_logprobs` or `logprobs`, so the other sampling parameters in the providers' guidance need no handling. `[Source: specs/010-model-aware-parameters/spec.md -> "Overtype sends no top_p"]`
- **AS-013**: No new network endpoint, no clipboard use, and no logging of selected text or model output are introduced. The adaptive retry is a second request to the same provider before any write, so the selection stays untouched (Principle II). `[Source: specs/010-model-aware-parameters/spec.md -> "No new network endpoint"]`
- **AS-014**: The SC-024, SC-025, SC-026 and SC-028 acceptance runs and the FR-054 diagnostic run use the user's own provider accounts and are recorded in `docs/compatibility.md`. `[Source: specs/010-model-aware-parameters/spec.md -> "The SC-001, SC-002, SC-003 and SC-005 acceptance runs"]`

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

### Revision: Archival 2026-08-04 (Reliable Selection Reading / Dormant AX Trees)

- Reason: Archived `specs/005-teams-ax-recovery`. IDs renumbered to FR-035–FR-040
  and SC-019–SC-023; original 005 IDs annotated inline. Two of the feature's
  requirements were **consolidated instead of appended**: orig FR-006
  (cancellation during the retry window) folded into FR-022 and orig FR-007
  (unchanged typed-error surface) folded into FR-023; both entries now carry two
  item-level source refs and their legacy 001 refs were upgraded in place. Two
  edge cases (context change mid-run; app that never exposes a selection) folded
  into the existing 001 entries for the same failure modes. A top-level
  `## Assumptions` section was created, matching the spec template's ordering.
- Recorded attempt count is **24 x 150 ms**, per the feature's FR-003, its plan,
  `docs/compatibility.md`, and `AXHelpers.recoveryAttempts`. The feature spec's
  Key Entities / Assumptions prose and its `data-model.md` still say the
  pre-amendment 12; those were left untouched as a stale-source note.
