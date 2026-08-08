# Feature Specification: Stability Hardening

**Feature Branch**: `009-stability-hardening`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "Stability hardening: fix the 7 critical (crash/data-loss) and 8 high-severity (reliability) defects found in the 2026-08-08 deep bug review of the whole app. No new features; every change traces to a finding (C1-C7, H1-H8); the medium/low backlog stays out of scope."

Traceability: every requirement below carries the finding id (C1-C7, H1-H8) from the
review. The reviewed code state is commit `eda5ad2` on `main`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Malformed configuration never crashes or resets the app (Priority: P1)

Hand-editing `config.json` is a documented, supported surface. Whatever value a
user (or a bad merge) puts there, the app must start, keep every valid provider
and action, and say visibly what it had to ignore. Today a single negative
shortcut value crashes the app at every launch with no in-app recovery (C1), and
a single wrong-typed field silently replaces the whole configuration with
defaults (C3).

**Why this priority**: crash-at-launch with no recovery path and whole-config
loss are the most severe failure modes found in the review.

**Independent Test**: launch the app against a fixture matrix of malformed
config files and verify: launch succeeds, valid entries survive, a non-silent
notice names what was dropped or defaulted.

**Acceptance Scenarios**:

1. **Given** an action whose stored shortcut has a negative `modifiers` or `keyCode` value, **When** the app launches, **Then** it starts normally, skips registering that shortcut, and logs a warning naming the action (C1).
2. **Given** a provider entry with one wrong-typed field (for example a string where a number belongs), **When** the configuration loads, **Then** only the affected value falls back or only the affected entry is skipped, all other providers and actions load, and the user sees a non-silent notice (C3).
3. **Given** `"showHUD": "true"` written as a string, **When** the configuration loads, **Then** the field falls back to its default and the rest of the configuration is preserved (C3).
4. **Given** a provider whose base URL string is not a valid URL, **When** the configuration loads, **Then** that provider loads without a base URL (failing later with the existing typed error at run time) instead of destroying the whole configuration (C3).

---

### User Story 2 - A replacement write never silently loses text (Priority: P1)

From the moment the app deletes the selection, it must either deliver the full
validated replacement or state clearly that it failed. It must never report
success while text is missing. Today a configured chunk size of `0` sends the
whole replacement as one oversized synthetic event, most of which is silently
dropped (C2), and a failed event creation silently skips a chunk while the run
still reports success (H3).

**Why this priority**: the constitution calls a single incident of destroyed
user text unrecoverable reputational damage (Principle II).

**Independent Test**: run actions with hostile cadence configuration and induced
write failures; verify complete output or an explicit partial-write error.

**Acceptance Scenarios**:

1. **Given** `"typingChunkSize": 0` (or a negative value) in configuration, **When** an action runs, **Then** the replacement is typed completely, in chunks bounded to the verified safe size (C2).
2. **Given** a synthetic event cannot be created mid-write, **When** the write stops, **Then** the run ends with a specific error stating the document may be partially replaced, and never with a success indication (H3).
3. **Given** the user is still holding Shift shortly after triggering the action, **When** the write is about to start, **Then** the app waits for Shift release exactly as it does for Command, Option, and Control (H8).

---

### User Story 3 - Settings edits and credentials survive every save path (Priority: P2)

Whatever the user does in Settings, and however a save fails, the app must not
lose a stored API key (C4), must not let two Settings windows silently revert
each other (C5), must not duplicate records on retry after a failed save (C6),
and must not overwrite hand edits made to the configuration file while the app
runs (C7).

**Why this priority**: these are silent data-loss paths in everyday flows, one
step below P1 only because they do not destroy document text.

**Independent Test**: exercise the save/fail/retry, dual-window, external-edit,
and credential-failure flows and verify no loss, no duplication, no divergence
between UI state and the file.

**Acceptance Scenarios**:

1. **Given** saving a new action fails (for example because of an invalid override row on another tab), **When** the user fixes the cause and saves again, **Then** exactly one action exists (C6).
2. **Given** a failed toggle or failed save, **When** the error is shown, **Then** the visible UI state matches the persisted configuration (C6).
3. **Given** the Settings UI is open twice (menu bar window plus the system settings shortcut), **When** the user saves in either window, **Then** nothing saved from the other window is lost (C5).
4. **Given** the credential store cannot persist a newly entered API key, **When** the save fails, **Then** the previously stored key is still present and the error names the underlying status (C4).
5. **Given** the user hand-edits `config.json` while the app is running, **When** they open Settings with no unsaved edits, **Then** the UI shows the edited values, and a subsequent save does not revert the hand edits (C7).

---

### User Story 4 - Runs stay cancellable and truthful under adverse conditions (Priority: P2)

Escape must abort a run within a bounded time even when the target application
is frozen (H1), a completed accessibility recovery must not permanently change
how the app talks to every other application (H2), and revoking the
Accessibility permission mid-session must produce a permission-specific error
plus automatic recovery of Escape monitoring after re-grant (H4).

**Why this priority**: these defects make the app appear hung or broken in ways
the user cannot diagnose, violating the no-silent-failure principle.

**Independent Test**: run against an intentionally unresponsive target, revoke
and re-grant the permission mid-session, and run the Teams dormant-tree
acceptance scenario before and after a recovery.

**Acceptance Scenarios**:

1. **Given** the target application is unresponsive, **When** the user presses Escape while the HUD shows "Reading...", **Then** the run aborts within a bounded, documented time (H1).
2. **Given** a run already performed dormant-tree recovery, **When** later runs execute against other applications, **Then** accessibility behavior matches a fresh launch (no permanent process-wide timeout change) (H2).
3. **Given** the Accessibility permission was revoked after launch, **When** the user triggers an action, **Then** the error names the missing permission (not a generic "cannot find text element"), and after re-granting, Escape cancellation works again without relaunching (H4).

---

### User Story 5 - Provider responses handled robustly, diagnostics usable (Priority: P3)

The OpenAI-compatible provider (the default kind, pointed at arbitrary servers)
must not type model scratch work into the document and must report refusals,
filtered output, and empty output with the same typed errors the other providers
use (H5). The local-model truncation guard must actually be able to fire (H6).
The unified log must be readable and the documented debug mode reachable, with
the privacy warning the constitution requires (H7).

**Why this priority**: wrong-output and diagnosability defects; serious, but
they do not destroy data by themselves.

**Independent Test**: drive the provider parsing with recorded response shapes
(reasoning markers, refusal, content filter, empty), check the truncation
threshold math against large-window models, and inspect live unified-log output.

**Acceptance Scenarios**:

1. **Given** an OpenAI-compatible server that inlines reasoning markers in the response, **When** the response is processed, **Then** the reasoning block is stripped and never typed into the document (H5).
2. **Given** a refusal response with null content, **When** it is processed, **Then** the user sees the specific blocked-response error, not a generic failure (H5).
3. **Given** a local model whose trained context window is far larger than the requested one, **When** the runtime reports a prompt size consistent with truncation, **Then** the truncation guard detects it (H6).
4. **Given** debug logging is enabled through the documented switch, **When** the app logs, **Then** unified-log output is readable and an explicit privacy warning was emitted at enablement (H7).

---

### Edge Cases

- Shortcut values that are negative, zero, or far beyond valid key-code ranges (C1).
- Chunk size zero, negative, or absurdly large; replacement text consisting only of surrogate-pair characters at chunk boundaries (C2).
- Configuration with empty `providers`/`actions` arrays, or where every element is invalid (C3: app must still start on defaults with a notice).
- Credential store locked or access denied at the moment of save (C4).
- Both Settings windows holding unsaved edits at once (C5: last save wins per field is acceptable; silent loss of a previously saved change is not).
- External config edit that arrives while the Settings window has unsaved edits (C7: unsaved edits win; no silent overwrite of either side without a save action).
- Escape pressed during dormant-tree recovery, during the retry pause, and during the modifier wait (already cancellable; must remain so after H1 changes).
- Permission revoked between the read and the write of a single run (existing context re-check must still abort the write).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** (C1): The application MUST start successfully regardless of any numeric value stored in a configured shortcut; an invalid shortcut MUST be skipped with a logged warning naming the action, and MUST never terminate the app.
- **FR-002** (C2): Typing cadence values from every source (global, per-app override, hand edit, UI entry) MUST be constrained to a safe range before use, and no single synthetic typing event may carry more text than the empirically verified safe size.
- **FR-003** (C3): Configuration loading MUST tolerate wrong-typed values and invalid entries: a field with a default falls back per field; an entry that cannot be salvaged is skipped by itself; all remaining data loads. Whenever anything was dropped or defaulted, the user MUST receive a non-silent notice.
- **FR-004** (C4): Storing a credential MUST NOT remove the previously stored credential unless the new one has been durably written; every credential-store failure MUST carry the underlying status code into the user-visible error.
- **FR-005** (C5): All Settings surfaces MUST operate on one shared draft state, so a save from any window can never revert changes already saved from another.
- **FR-006** (C6): After a failed settings save, the in-memory state MUST equal the persisted state (full rollback), for every mutator, matching the rollback already implemented for provider mutations.
- **FR-007** (C7): Opening Settings with no unsaved edits MUST reflect the configuration file's current on-disk content, including edits made outside the app while it runs.
- **FR-008** (H1): A run MUST be cancellable during the read phase within a bounded time even when the target application is unresponsive, and the read phase MUST be covered by a hard timeout (constitution Principle VI).
- **FR-009** (H2): Accessibility recovery MUST NOT permanently alter process-wide accessibility behavior; any global adjustment made for recovery MUST be restored when recovery ends.
- **FR-010** (H3): If any part of the replacement cannot be delivered after the destructive delete, the run MUST end with a specific error stating that the document may be partially replaced; it MUST NOT report success.
- **FR-011** (H4): Accessibility trust MUST be evaluated at the start of every run; a missing permission MUST produce a permission-specific error, and Escape monitoring MUST recover automatically once the permission is restored, without relaunching.
- **FR-012** (H5): The OpenAI-compatible provider MUST strip leading reasoning blocks, MUST map refusals and content-filter stops to the blocked-response error, MUST map empty output to the empty-response error, and MUST distinguish a missing credential from a credential-store failure in its warning logs.
- **FR-013** (H6): Prompt-truncation detection for local models MUST be computed against the effective context window (the smaller of the requested and the trained window), so that it can fire for models of any size.
- **FR-014** (H7): Unified-log output MUST be readable (correct format usage), and the documented debug logging mode MUST be reachable via a persistent switch that emits an explicit privacy warning when enabled (closes the corresponding Known Deviation in constitution v1.1.0).
- **FR-015** (H8): The pre-write modifier wait MUST include Shift, and all synthetic typing events MUST carry cleared modifier flags, consistent with the existing key-press path.
- **FR-016** (cross-cutting): All existing unit tests MUST keep passing; every fix containing pure logic MUST gain unit tests; every accessibility or synthetic-event change MUST have a manual acceptance entry recorded in `docs/compatibility.md` (constitution Principle VIII).

### Key Entities

- **Configuration**: the persisted global preferences, provider records, and action records; the subject of C1, C2, C3, C5, C6, C7. Its integrity across load, save, and external edits is the core of this feature.
- **Credential**: an API key stored in the system keychain, referenced by a provider record; the subject of C4 and part of H5.
- **Run**: one hotkey-triggered read/transform/write cycle; the subject of C2, H1, H2, H3, H4, H8.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The app launches successfully with 100% of the malformed-configuration fixture matrix (at minimum: negative shortcut modifiers, chunk size 0, wrong-typed boolean, invalid base URL string, unknown provider kind), and in each case every valid provider and action survives.
- **SC-002**: With an unresponsive target application, pressing Escape during the read phase aborts the run in at most 5 seconds (today this can exceed a minute).
- **SC-003**: No code path reports success while the typed output is incomplete: every partial-delivery path ends in a visible, specific error.
- **SC-004**: A credential-save failure never leaves the user without the previously working credential.
- **SC-005**: The full existing unit-test suite (229 tests) keeps passing, and new tests cover each pure-logic fix (shortcut validation, cadence clamping, lossy configuration decoding, provider response parsing, truncation threshold).
- **SC-006**: The manual acceptance matrix in `docs/compatibility.md` is re-run for the changed accessibility and typing behaviors with no regression against previously recorded results.
- **SC-007**: After a mid-session permission revoke and re-grant, cancellation works again without an app relaunch.

## Assumptions

- The defect list and severity ranking come from the 2026-08-08 review of commit `eda5ad2`; the approved fix plan is the authoritative scope description, and its medium/low backlog is explicitly out of scope here.
- Keychain item identity stays account-only (no service attribute is added), so existing stored credentials keep working without migration; this trade-off is documented in code (C4).
- The practical size cap for one synthetic typing event is assumed to be near 20 UTF-16 units pending the diagnostic run required by Principle III; the C2 fix must be safe regardless of the exact cap by bounding chunk size to the verified value.
- The debug-logging switch (H7) is a persistent flag set outside the UI (no new Settings surface), consistent with the "no new features" constraint; it repairs a documented but unreachable mode and closes a Known Deviation already recorded in the constitution.
- Dual-window behavior (C5) is resolved by sharing draft state, not by removing either entry point; simultaneous unsaved edits follow last-save-wins per the shared draft.
- Existing typed errors are reused wherever they fit; new error cases are added only where no existing case describes the failure (H3 partial write, H4 permission missing).
