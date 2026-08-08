# Tasks: Stability Hardening

**Input**: Design documents from `/specs/009-stability-hardening/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included (mandatory here: constitution Principle VIII and FR-016 require unit
tests for every pure-logic fix). Test tasks come first within each story and must fail
before the fix lands.

**Organization**: Grouped by user story (US1..US5 from spec.md). Finding ids (C1-C7,
H1-H8) are carried on every task for traceability.

**Commit discipline** (user-directed): one commit at the end of each phase checkpoint,
Conventional Commits format, only with `swift test` green.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] T001 Verify green baseline: run `swift test` (229 tests expected) and `rg NSPasteboard Sources/ Vendor/` (no matches outside comments); no code changes

---

## Phase 2: Foundational

No foundational tasks: the five stories touch disjoint defects and share no new
infrastructure. (The shared reasoning stripper serves only US5 and is created there.)

---

## Phase 3: User Story 1 - Malformed configuration never crashes or resets the app (Priority: P1) 🎯 MVP

**Goal**: any config.json content launches the app, keeps all valid data, and produces a
non-silent notice for whatever was ignored (C1, C3).

**Independent Test**: unit suites for decoding plus the malformed-config fixture matrix
in quickstart.md section 2.

### Tests for User Story 1

- [X] T002 [P] [US1] Add failing tests: negative `modifiers`/`keyCode` decode and `keyboardShortcut` returning nil, valid values still working, in Tests/OvertypeTests/AppConfigTests.swift (C1)
- [X] T003 [P] [US1] Add failing tests: wrong-typed defaulted scalars fall back, invalid `baseURL` string yields nil, per-element drop for unknown `kind` and missing required fields, `displayString` defaults to empty, issue strings name keys/ids only, in Tests/OvertypeTests/AppConfigTests.swift (C3)

### Implementation for User Story 1

- [X] T004 [US1] Make `ActionShortcut.keyboardShortcut` optional: nil when `keyCode < 0 || modifiers < 0`, convert via `UInt(bitPattern:)` after the guard, in Sources/Overtype/Config/AppConfig.swift (C1)
- [X] T005 [US1] Skip nil shortcuts with a `.warning` naming the action in Sources/Overtype/Core/HotkeyManager.swift; seed the recorder only from a non-nil value in Sources/Overtype/UI/Settings/ActionsTab.swift (C1)
- [X] T006 [US1] Implement `ConfigDecodingIssues` collector (via `JSONDecoder.userInfo`), `FailableDecodable` element wrapper, type-tolerant defaulted scalars, `baseURL` as string + `URL(string:)`, `displayString` default, in Sources/Overtype/Config/AppConfig.swift (C3)
- [X] T007 [US1] Pass the collector from `ConfigStore`, add `loadWarningMessage`, log each issue at `.warning`, in Sources/Overtype/Config/ConfigStore.swift (C3)
- [X] T008 [US1] Surface `loadWarningMessage` through the existing launch alert path in Sources/Overtype/OvertypeApp.swift (C3)
- [X] T009 [US1] Checkpoint: `swift test` fully green; commit `fix(config): tolerate malformed values without crash or config loss`

---

## Phase 4: User Story 2 - A replacement write never silently loses text (Priority: P1)

**Goal**: after the destructive delete, either the full replacement is typed or a typed
error says it may be incomplete (C2, H3, H8).

**Independent Test**: cadence clamp unit tests plus quickstart.md section 3 (write
integrity) and the event-cap diagnostic.

### Tests for User Story 2

- [ ] T010 [P] [US2] Add failing clamp tests: chunk 0, negative, 21+, boundary 1 and 20, override and global paths, delay floor at 0, in Tests/OvertypeTests/TypingProfileTests.swift (C2)

### Implementation for User Story 2

- [ ] T011 [US2] Clamp resolved chunk size to `1...20` and delay to `>= 0` in `TextWriter.typingProfile`; defensive `chunkRanges` fallback to default-size chunks; `.warning` log at the call site when the clamp engages, in Sources/Overtype/Core/TextWriter.swift (C2)
- [ ] T012 [US2] Set `minimum = 0` on the three cadence `NumberFormatter`s in Sources/Overtype/UI/Settings/GeneralTab.swift (C2)
- [ ] T013 [US2] Add `AXError.writeIncomplete` (message: replacement may be incomplete) in Sources/Overtype/Support/AXHelpers.swift; throw it instead of `continue` on CGEvent creation failure, with an `.error` log carrying chunk index/count only, in Sources/Overtype/Core/TextWriter.swift (H3)
- [ ] T014 [US2] Add `.maskShift` to the modifier-release wait; set `flags = []` on chunk eventDown/eventUp; update the quirk comment to match, in Sources/Overtype/Core/TextWriter.swift (H8)
- [ ] T015 [US2] Checkpoint: `swift test` fully green; commit `fix(writer): bound chunks, surface partial writes, wait for Shift`

---

## Phase 5: User Story 3 - Settings edits and credentials survive every save path (Priority: P2)

**Goal**: no lost credential, no dual-draft reverts, no duplicates on retry, no
overwritten hand edits (C4, C5, C6, C7).

**Independent Test**: unit tests for the pure parts plus quickstart.md section 5.

### Tests for User Story 3

- [ ] T016 [P] [US3] Add failing tests for `KeychainError` `LocalizedError` rendering (status code visible, message text present) in Tests/OvertypeTests/KeychainErrorTests.swift (C4)
- [ ] T017 [P] [US3] Add failing tests for the unsaved-edit/adopt decision logic (clean draft adopts, dirty draft keeps, snapshot refresh on save) in Tests/OvertypeTests/SettingsReloadTests.swift (C7)

### Implementation for User Story 3

- [ ] T018 [US3] Rework `store`: attribute-only search, `SecItemUpdate` else `SecItemAdd`, never delete first; `KeychainError: LocalizedError` with `OSStatus` + `SecCopyErrorMessageString`; account-only identity trade-off comment, in Sources/Overtype/Security/KeychainStore.swift (C4)
- [ ] T019 [US3] Single shared draft: `SettingsViewModel.shared`; `SettingsWindow` consumes it via `@ObservedObject` (default `.shared`), in Sources/Overtype/UI/Settings/SettingsViewModel.swift and Sources/Overtype/UI/Settings/SettingsWindow.swift (C5)
- [ ] T020 [US3] Rollback on `saveSettings()` throw in `saveAction` (create: removeLast; edit: restore original) and `toggleActionEnabled` (un-toggle), in Sources/Overtype/UI/Settings/SettingsViewModel.swift (C6)
- [ ] T021 [US3] `lastLoaded` snapshot (init + after successful save); `reloadFromDisk()` calls `ConfigStore.shared.reload()` (throw: warn, keep state), adopts the store config when the draft is clean, rebuilds overrides, posts `.overtypeConfigDidChange`, in Sources/Overtype/UI/Settings/SettingsViewModel.swift (C7)
- [ ] T022 [US3] Checkpoint: `swift test` fully green; commit `fix(settings): atomic keychain writes, shared draft, rollback, real reload`

---

## Phase 6: User Story 4 - Runs stay cancellable and truthful under adverse conditions (Priority: P2)

**Goal**: Escape aborts within 5 s against a frozen target, the read phase hard-times-out
at 30 s, recovery leaves no process-global residue, and a revoked permission is named and
self-heals (H1, H2, H4).

**Independent Test**: quickstart.md sections 4 and 6 (manual; system boundary), plus
compilation-level unit coverage where pure.

### Implementation for User Story 4

- [ ] T023 [US4] Add `try Task.checkCancellation()` before each lookup strategy and at every DFS node (DFS becomes throwing), in Sources/Overtype/Support/AXHelpers.swift (H1)
- [ ] T024 [US4] Add `withBoundedAXMessaging(_:)` (system-wide 2 s timeout on entry, restore to 0 in `defer`), wrap the read-phase lookup in it, remove the permanent system-wide timeout from `retryFocusLookup`, keep all quirk comments, in Sources/Overtype/Support/AXHelpers.swift (H2)
- [ ] T025 [US4] Wrap `readSelection()` in a 30 s hard-timeout race (task group, loser cancelled, timeout throws new `AXError.readTimedOut` naming the unresponsive target), in Sources/Overtype/Core/ActionEngine.swift and Sources/Overtype/Support/AXHelpers.swift (H1)
- [ ] T026 [US4] Per-run trust check: `AXIsProcessTrusted()` at `run` start; new `AXError.accessibilityPermissionRevoked`; post `.overtypeAccessibilityTrustLost`; AppDelegate observer starts the existing poll/reinstall timer when not already running, in Sources/Overtype/Core/ActionEngine.swift, Sources/Overtype/Support/AXHelpers.swift, Sources/Overtype/OvertypeApp.swift (H4)
- [ ] T027 [US4] Checkpoint: `swift test` fully green; commit `fix(ax): cancellable bounded reads, scoped timeouts, per-run trust check`

---

## Phase 7: User Story 5 - Provider responses handled robustly, diagnostics usable (Priority: P3)

**Goal**: the default provider kind reaches parity with the defended providers, the
truncation guard can fire for any model, logs are readable, debug mode reachable
(H5, H6, H7).

**Independent Test**: new provider unit suite, threshold unit tests, quickstart.md
sections 7 and 8.

### Tests for User Story 5

- [ ] T028 [P] [US5] Add failing `OpenAICompatibleProviderTests`: endpoint URL building (trailing slash both ways), refusal, `finish_reason == "content_filter"`, null/missing content, empty content, reasoning-block strip, error-body extraction, per contracts/openai-response-handling.md, in Tests/OvertypeTests/OpenAICompatibleProviderTests.swift (H5)
- [ ] T029 [P] [US5] Add failing threshold tests: trained windows 40960 and 131072 both yield truncation threshold 8192, in Tests/OvertypeTests/OllamaProviderTests.swift (H6)

### Implementation for User Story 5

- [ ] T030 [US5] Extract the leading-reasoning-block stripper into a shared pure helper in Sources/Overtype/Providers/ (new file); `OllamaProvider` delegates to it; all existing OllamaProviderTests stay green, in Sources/Overtype/Providers/OllamaProvider.swift (H5)
- [ ] T031 [US5] Add `endpointURL`/`parseResponseText` seams; map refusal and content-filter to `.responseBlocked(reason:)` (short category), null/invalid to `.invalidResponse`, empty to `.emptyResponse`; strip reasoning on the happy path; Keychain catch distinguishes `itemNotFound` from other statuses with a `.warning` naming key and status only, in Sources/Overtype/Providers/OpenAICompatibleProvider.swift (H5)
- [ ] T032 [US5] Clamp `grantedContextWindow` to `min(contextWindowTokens, reported)`; correct the comment to state both clamp directions, in Sources/Overtype/Providers/OllamaProvider.swift (H6)
- [ ] T033 [US5] Switch to `os_log("%{public}@", ...)`; initialize `isDebugEnabled` from `UserDefaults` key `OvertypeDebugLogging`; log one `.warning` privacy notice when enabled, in Sources/Overtype/Support/Logger.swift; AND present a visible launch alert (existing alert path) when the flag is on, naming the privacy consequence and how to disable it, in Sources/Overtype/OvertypeApp.swift (H7, Principle V)
- [ ] T034 [US5] Checkpoint: `swift test` fully green; commit `fix(providers): harden openai-compatible parsing, ollama window clamp, logging`

---

## Phase 8: Polish & Cross-Cutting

- [ ] T035 Full verification pass: `swift test`, `rg NSPasteboard Sources/ Vendor/`, and an audit of every log line added by this feature (keys, ids, titles, counts, statuses only; no selected text, prompts, output, or key values)
- [ ] T036 [P] Update project docs where behavior changed: CLAUDE.md (config tolerance, debug switch, read-phase timeout, scoped AX messaging) and README hand-editing notes if they describe decode failure behavior
- [ ] T037 Add the new manual acceptance scenarios (from quickstart.md sections 2-6) as pending entries in docs/compatibility.md so results can be recorded per app
- [ ] T038 Checkpoint: `swift test` fully green; commit `docs(spec): polish, docs, and acceptance scaffolding for stability hardening`

---

## Phase 9: Manual Acceptance (user-run, outside the agent session)

These require the real GUI, target applications, and permission toggling. They are
executed by the user per quickstart.md and recorded in docs/compatibility.md. They are
NOT unbuilt code: the converge loop must not treat them as implementation gaps.

- [ ] T039 [MANUAL] Malformed-config launch matrix (quickstart.md section 2) recorded in docs/compatibility.md (SC-001)
- [ ] T040 [MANUAL] Write-integrity run and synthetic-event cap diagnostic, including the surrogate boundary case (quickstart.md section 3) recorded in docs/compatibility.md (C2, SC-003)
- [ ] T041 [MANUAL] Frozen-target Escape (5 s) and hard timeout (30 s), plus Teams dormant-tree re-run and post-recovery behavior (quickstart.md section 4) recorded in docs/compatibility.md (SC-002, H2)
- [ ] T042 [MANUAL] Settings integrity: dual window, failed-save retry, external edit, locked-keychain credential save (quickstart.md section 5) recorded in docs/compatibility.md (SC-004, C5, C6, C7)
- [ ] T043 [MANUAL] Permission revoke and re-grant mid-session (quickstart.md section 6) recorded in docs/compatibility.md (SC-007)
- [ ] T044 [MANUAL] Outlook and Teams typing re-run after H8 flag changes (quickstart.md section 3) recorded in docs/compatibility.md (H8)

---

## Dependencies & Execution Order

- Phase 1 first (baseline evidence).
- Phase 2 is empty; user stories are mutually independent and can proceed in any order;
  the committed order is P1 to P3 (Phases 3, 4, 5, 6, 7).
- Within each story: test tasks ([P], different files) precede implementation; the
  checkpoint task is always last.
- Phase 8 after all implemented stories. Phase 9 is user-run and gates the release, not
  the merge of code phases (constitution VIII gates the release on recorded results).

### Parallel Opportunities

- T002/T003 together; T010 alongside nothing (single file); T016/T017 together;
  T028/T029 together; T036 parallel to T037.
- Different user stories touch disjoint files and could be developed in parallel;
  the committed flow is sequential to honor one-commit-per-stage.

## Implementation Strategy

MVP is Phase 3 (US1): after it, no configuration content can crash or reset the app.
Each subsequent phase is an independently verifiable increment ending in its own commit.
`swift test` must be green at every checkpoint; a phase is not committed otherwise.
