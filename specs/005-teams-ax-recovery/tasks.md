# Tasks: Reliable Selection Reading for Apps with Dormant Accessibility Trees

**Input**: Design documents from `/specs/005-teams-ax-recovery/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: No new unit tests required (the change is system-boundary code, exempt
from mock-based tests per constitution Principle VIII; no new pure logic is
introduced). The existing suite must stay green. Verification is the manual
acceptance procedure in quickstart.md, executed against real applications.

**Organization**: All three user stories are exercised by one small code change
in `AXHelpers.getFocusedElement` plus its opt-in call site; the story phases
below separate the code increments from their independent verifications.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] T001 Confirm green baseline: run `swift test` and `swift build` on branch `005-teams-ax-recovery`; record any pre-existing failures before touching code

---

## Phase 2: Foundational

No foundational tasks. The feature builds entirely on existing code.

---

## Phase 3: User Story 1 - Fix text in Teams after Teams has restarted (Priority: P1) 🎯 MVP

**Goal**: A cold-restarted Teams recovers automatically: wake flags + bounded retry make the first run succeed.

**Independent Test**: quickstart.md scenario B (cold Teams restart, first run succeeds without external warm-up).

### Implementation for User Story 1

- [X] T002 [US1] Add private `wakeDormantAccessibilityTree(appElement:)` helper in `Sources/Overtype/Support/AXHelpers.swift`: set `AXEnhancedUserInterface` and `AXManualAccessibility` to true on the app element, explicitly discarding both returned `AXError` values, with QUIRK comments naming (a) Teams returning `.notImplemented` while honoring the write (verified 2026-08-02) and (b) `AXManualAccessibility` being the Electron variant rejected by Teams (axprobe findings 2026-07-31)
- [X] T003 [US1] Add private `retryFocusLookup(appElement:)` in `Sources/Overtype/Support/AXHelpers.swift`: `AXUIElementSetMessagingTimeout(2.0)` on the app element and a fresh system-wide element; loop 12 attempts at 150 ms (`try Task.checkCancellation()` first each iteration, same idiom as `TextWriter.writeViaCGEvent`); each attempt queries app-element `kAXFocusedUIElementAttribute` first, system-wide second; return immediately on an element with non-empty `kAXSelectedText`; remember a selection-less element as fallback candidate and keep retrying; after the loop return the candidate or nil
- [X] T004 [US1] Change `getFocusedElement` signature in `Sources/Overtype/Support/AXHelpers.swift` to `getFocusedElement(wakeDormantTree: Bool = false)`: when all existing strategies fail AND `wakeDormantTree` is true, call T002's wake helper then T003's retry lookup before the existing fallback-candidate/`noFocusedElement` conclusion; existing behavior byte-for-byte identical when the flag is false or when any strategy succeeds; log the recovery entry and outcome (attempt count, no selected text content) at appropriate levels
- [X] T005 [US1] Opt in from the read path: in `Sources/Overtype/Core/SelectionReader.swift`, call `AXHelpers.getFocusedElement(wakeDormantTree: true)`; leave the `ActionEngine` pre-write re-check call site untouched (single-shot, per plan Design Decision 1)
- [X] T006 [US1] Build and test: `swift build` and `swift test` pass; `rg NSPasteboard Sources/` returns no match outside comments
- [ ] T007 [US1] MANUAL (requires user at the machine): execute quickstart.md scenario B twice from cold Teams restarts (SC-001, SC-005); rebuild via `./scripts/build-app.sh`, re-grant Accessibility permission first

**Checkpoint**: Cold-Teams recovery works; this alone is the MVP.

---

## Phase 4: User Story 2 - No regression for well-behaved apps (Priority: P2)

**Goal**: Fast path unchanged; no flags set and no delay added when the existing strategies succeed.

**Independent Test**: quickstart.md scenario C.

- [X] T008 [US2] Code-level guarantee review of `Sources/Overtype/Support/AXHelpers.swift`: confirm the recovery block is reachable only after strategies 1-5 have all failed and only with `wakeDormantTree == true`; confirm no timing/behavior change on any success path (self-review against the 1164c7c..HEAD-style diff of the function)
- [ ] T009 [US2] MANUAL (requires user at the machine): execute quickstart.md scenario C (warm Teams, New Outlook, one native app) and confirm unchanged latency and no recovery log lines (SC-002)

**Checkpoint**: No regression observed in previously working apps.

---

## Phase 5: User Story 3 - Failures still fail fast and clearly (Priority: P3)

**Goal**: Bounded failure timing, unchanged typed errors, prompt Escape cancellation during the retry window.

**Independent Test**: quickstart.md scenario D.

- [X] T010 [US3] Verify error/cancellation surface in `Sources/Overtype/Support/AXHelpers.swift` and `Sources/Overtype/Core/ActionEngine.swift`: recovery exhaustion still ends in the existing `noFocusedElement` / `cannotReadSelectedText` typed errors; `CancellationError` thrown inside the retry loop propagates to `ActionEngine`'s existing `catch is CancellationError` path (no new error cases introduced)
- [ ] T011 [US3] MANUAL (requires user at the machine): execute quickstart.md scenario D (nothing-selected timing within the bounded recovery window, SC-003; Escape during recovery cancels < 1 s with document untouched, SC-004)

**Checkpoint**: All three stories verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T012 [P] Update `docs/compatibility.md`: add the Teams dormant-tree entry (cold-restart behavior, wake-flag quirk including the misleading `.notImplemented` return code, bounded recovery window) and record dated results of quickstart scenarios B-E
- [ ] T013 [P] Run quickstart.md scenario E regression sweep (Outlook, native app, VS Code if available) and record outcomes in `docs/compatibility.md`
- [X] T014 Final PR checklist pass: no `NSPasteboard` in `Sources/`; no selected text/model output logged at info+ by the new code; every new boundary workaround commented; `swift test` green

---

## Dependencies & Execution Order

- **Phase 1 (T001)** first.
- **US1**: T002 and T003 are [P]-eligible in principle but touch the same file, so do them sequentially; T004 depends on T002+T003; T005 on T004; T006 on T005; T007 (manual) on T006.
- **US2 (T008-T009)** and **US3 (T010-T011)** depend on US1's code being complete (same function); their manual checks can run in any order after T006.
- **Polish**: T012 and T013 can proceed in parallel after the manual scenarios; T014 last.

## Implementation Strategy

MVP is US1 alone (T001-T007). US2/US3 are verification-heavy and share US1's
code, so the practical order is: implement T002-T006, then run the manual
scenarios B, C, D, E in one sitting with the user at the machine, then T012-T014.
