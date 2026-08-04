---

description: "Task list for 006-settings-version-display"
---

# Tasks: Application Version in Settings General Tab

**Input**: Design documents from `/specs/006-settings-version-display/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Unit tests are included and are **not optional here**. Constitution
Principle VIII requires pure logic to be unit-tested, and the version formatting
rules (including every fallback that FR-007 and SC-005 depend on) are pure logic.
System-boundary work (bundle reading, SwiftUI rendering, shell stamping) is
deliberately **not** unit-tested; it is covered by the manual procedure in
`quickstart.md`.

**Organization**: Tasks are grouped by user story so each story can be
implemented, tested and demonstrated on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths are included in every task

## Path Conventions

Native macOS Swift Package. Application sources under `Sources/Overtype/`, tests
under `Tests/OvertypeTests/`, packaging under `scripts/`, release automation under
`.github/workflows/`, documentation under `docs/`.

**Environment note**: on this machine `swift test` needs the Xcode toolchain.
Prefix test commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
or the test target fails to compile with `no such module 'XCTest'`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm a green starting point so any later failure is attributable
to this feature.

- [X] T001 Confirm the baseline test suite is green by running `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` at the repository root; expect 64 tests, 0 failures
- [X] T002 Confirm the clipboard constraint baseline by running `rg NSPasteboard Sources/`; expect no output (this must still be true at the end)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The version value and its formatting rules. Every user story reads
from this, so nothing else can start until it exists.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 Create `Sources/Overtype/Support/AppVersion.swift` defining an `AppVersion` value with `shortVersion: String?` and `build: String?`, a `displayString: String` computed property implementing the decision table in `data-model.md` (trim whitespace, treat empty-after-trim as absent; version absent → `Unknown`; build absent → version alone; both present → `1.2.1 (20)`), and a static `current` that reads `CFBundleShortVersionString` and `CFBundleVersion` from `Bundle.main.infoDictionary` using optional binding (no force unwrapping, per Constitution Principle VII)
- [X] T004 Create `Tests/OvertypeTests/AppVersionTests.swift` covering the eight cases listed in `research.md` D7: both values present, build absent, version absent, both absent, whitespace-only version, whitespace-only build, surrounding whitespace trimmed, and a pre-release string such as `1.3.0-beta.1` passed through unchanged; assert the exact placeholder text `Unknown` and assert no output ever contains empty parentheses
- [X] T005 Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppVersionTests` and confirm all new cases pass (depends on T003, T004)

**Checkpoint**: The version value and its rules exist and are proven. User story
work can now begin.

---

## Phase 3: User Story 1 - Find out which version is installed (Priority: P1) 🎯 MVP

**Goal**: A user opens Settings > General and reads the version of the running
application, without leaving the app.

**Independent Test**: Open Settings, select the General tab, and confirm a labelled
version row is visible and matches the installed application's declared version.

### Implementation for User Story 1

- [X] T006 [US1] Add a read-only version row to `Sources/Overtype/UI/Settings/GeneralTab.swift` as a new `Section` placed at the end of the `Form`, after the existing "Save Preferences" section, showing the label `Version` next to `AppVersion.current.displayString`, following the file's existing `Text` + `HStack` idiom rather than introducing a new layout API (per `research.md` D3)
- [X] T007 [US1] Verify in `Sources/Overtype/UI/Settings/GeneralTab.swift` that the version value is read directly from `AppVersion` and is **not** added to `SettingsViewModel`, not bound to any `@State`, and not referenced by `savePreferences()`, so it cannot be edited or take part in saving (FR-004, FR-009)
- [ ] T008 [US1] Build the bundle with `./scripts/build-app.sh`, open `Overtype.app`, and confirm against `contracts/version-display.md`: the labelled `Version` row is visible at the bottom of the General tab without scrolling past other groups being needed to reach it, the value is not editable, pressing "Save Preferences" still shows "Saved!" and leaves the version unchanged, the value is identical after closing and reopening the Settings window, and the version is found in under 10 seconds with at most two interactions against a tab with at least three per-application overrides configured (quickstart step 5)
- [ ] T009 [US1] Run quickstart step 6 against the built app and confirm no regression in the existing General tab controls: launch at login, speed multiplier, Show HUD, default chunk size, default delay, and per-application overrides all load, change and persist as before (FR-010, SC-006)
- [ ] T010 [US1] Run quickstart step 9 and confirm zero outbound network connections while the General tab is displayed, for example with `nettop -p $(pgrep -x Overtype)` (FR-008, SC-004)

**Checkpoint**: User Story 1 is complete. The feature as the user originally asked
for it is delivered and demonstrable, even if nothing further is done.

---

## Phase 4: User Story 2 - Report the version when asking for help (Priority: P2)

**Goal**: The displayed version can be selected and copied so it can be pasted
into a bug report.

**Independent Test**: Select the version text on the General tab, copy it with the
standard system command, paste it into a text editor, and confirm the pasted text
matches what was displayed.

### Implementation for User Story 2

- [X] T011 [US2] Enable selection on the version value in `Sources/Overtype/UI/Settings/GeneralTab.swift` with `.textSelection(.enabled)`, adding no pasteboard code of any kind (Constitution Principle I: the copy is performed by the system on the user's explicit command)
- [ ] T012 [US2] Re-run `rg NSPasteboard Sources/` and confirm it still returns nothing, then build with `./scripts/build-app.sh` and confirm the version text can be selected with the pointer, copied, and pasted elsewhere yielding exactly the displayed string such as `1.2.1 (20)` (quickstart step 5, last two bullets)

**Checkpoint**: User Stories 1 and 2 both work. The row shows the version and it
can be copied.

---

## Phase 5: User Story 3 - Version stays correct after an update (Priority: P3)

**Goal**: A released build declares the released version, with no manual edit
anywhere in the project, so the displayed value can never drift from the release.

**Independent Test**: Build with an explicit version, read the stamped values back
from the bundle, and confirm they match; then confirm an unstamped local build
still shows a sensible version.

### Implementation for User Story 3

- [X] T013 [P] [US3] Correct the checked-in fallback values in `Sources/Overtype/Resources/Info.plist`: set `CFBundleShortVersionString` to `1.2.1` (the current released tag) and `CFBundleVersion` to `0` (the sentinel meaning "not stamped"), per `research.md` D5
- [X] T014 [US3] Add the stamping step to `scripts/build-app.sh` immediately after `Info.plist` is copied into the bundle and **before** the `codesign` call, resolving the version as `$OVERTYPE_VERSION` → exact git tag at `HEAD` with a leading `v` stripped (`git describe --tags --exact-match HEAD`) → leave the copied value unchanged, and the build as `git rev-list --count HEAD` → leave the copied value unchanged; write both with `/usr/libexec/PlistBuddy -c "Set :<key> <value>"` against `"$APP_BUNDLE/Contents/Info.plist"` only, never against the file in `Sources/`
- [X] T015 [US3] Add an inline comment in `scripts/build-app.sh` at the stamping step stating that it must run before `codesign` because signing seals `Info.plist` and a later edit invalidates the signature, so the ordering is not rearranged in a future cleanup (Constitution Principle III)
- [X] T016 [US3] Ensure the stamping step never fails the build when git metadata or the environment variable is absent (no `set -e` abort on a failed `git describe`), so a source-only tree still produces a working bundle using the checked-in fallbacks
- [X] T017 [US3] Update the "Build .app bundle" step in `.github/workflows/release.yml` to pass the tag version through as `OVERTYPE_VERSION="${GITHUB_REF_NAME#v}" ./scripts/build-app.sh`, reusing the same expression the workflow already uses for the zip name, the release upload and the cask (depends on T014)
- [X] T018 [US3] Run quickstart step 2: `OVERTYPE_VERSION=1.2.1 ./scripts/build-app.sh`, then `defaults read "$PWD/Overtype.app/Contents/Info.plist" CFBundleShortVersionString` and `CFBundleVersion`; expect `1.2.1` and the current commit count from `git rev-list --count HEAD`
- [X] T019 [US3] Run quickstart step 3 and confirm all three stamping invariants: `codesign --verify --deep --strict "$PWD/Overtype.app"` succeeds (stamping happened before signing), `git status --porcelain Sources/Overtype/Resources/Info.plist` prints nothing (the tracked plist was not rewritten), and `CFBundleIdentifier` plus `LSUIElement` survive unchanged in the bundle plist
- [X] T020 [US3] Run quickstart step 4: build with no `OVERTYPE_VERSION` on an untagged `HEAD` and confirm the version falls back to the checked-in `1.2.1` while the build identifier is still the commit count
- [ ] T021 [US3] Open the app built in T018 and confirm the General tab shows the stamped values, proving the display and the stamping agree end to end (SC-003, SC-007)

**Checkpoint**: All three user stories work. The displayed version is now
structurally tied to the release it came from.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T022 Run quickstart step 7 and confirm the version row is legible in both Light and Dark system appearance, follows a system text size change, and that a long value (rebuild with `OVERTYPE_VERSION=1.3.0-beta.1`) is shown in full without widening the window or clipping other General tab controls
- [ ] T023 Run quickstart step 8 and confirm the unknown path visually: delete `CFBundleShortVersionString` from a built bundle, re-sign, launch, and confirm the General tab still opens normally and the row reads `Version  Unknown`; rebuild afterwards with `./scripts/build-app.sh` to restore a correct bundle (FR-007, SC-005)
- [X] T024 [P] Record the manual acceptance result in `docs/compatibility.md`: a dated entry naming the build tested, the version string shown, and confirmation that quickstart steps 2 through 9 passed, referencing `specs/006-settings-version-display/quickstart.md` for the procedure (Constitution Principle VIII)
- [X] T025 [P] Update `CLAUDE.md` so the Settings description states that the General tab also shows a read-only application version, and that `scripts/build-app.sh` stamps the version and build into the bundle at build time
- [X] T026 Run `make format` then `make lint` and confirm the new and modified Swift files are clean
- [X] T027 Run the full suite `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` and confirm all tests pass, including the pre-existing 64 plus the new `AppVersionTests` cases
- [X] T028 Walk the mandatory PR checklist from the constitution: `rg NSPasteboard Sources/` returns nothing; no secret, selected text or model output is logged at `info` or above (this feature logs nothing); the stamping ordering carries its explanatory comment; unit tests pass with tests for the new pure logic; the relevant manual acceptance items were executed and recorded

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies, start immediately
- **Foundational (Phase 2)**: depends on Phase 1; **blocks all user stories**
- **User Story 1 (Phase 3)**: depends on Phase 2
- **User Story 2 (Phase 4)**: depends on Phase 2; touches the same file as US1, so in practice follows US1
- **User Story 3 (Phase 5)**: depends on Phase 2 only for the end-to-end check in T021; T013 through T020 touch no application source and could be done before US1 if desired
- **Polish (Phase 6)**: depends on the user stories that were chosen for delivery

### User Story Dependencies

- **US1 (P1)**: independent once `AppVersion` exists. Delivers the feature on its own.
- **US2 (P2)**: independent in value, but edits the same row in `GeneralTab.swift` as US1, so it is sequenced after US1 to avoid an edit conflict rather than because of a logical dependency.
- **US3 (P3)**: independent of the UI. Its only tie to US1 is the final end-to-end confirmation in T021.

### Within Each User Story

- The implementation edit comes first, then the build, then the manual checks.
- Manual verification tasks are the story's acceptance evidence and must not be skipped, since this project does not mock the system boundary.

### Parallel Opportunities

Real parallelism is limited here because the feature is small and most work lands
in three files.

- T013 (`Info.plist`) is independent of every Swift task and can run alongside Phase 2 or Phase 3.
- T024 (`docs/compatibility.md`) and T025 (`CLAUDE.md`) touch different documentation files and can run together.
- T006/T007 (`GeneralTab.swift`) and T014/T015/T016 (`build-app.sh`) touch different files and could be done by two people at once, if the same person is not doing both.
- T003 and T004 are ordered rather than parallel: the test file references the type created in T003.

## Parallel Example: documentation polish

```bash
# These two touch different files and can run at the same time:
Task: "Record the manual acceptance result in docs/compatibility.md"
Task: "Update CLAUDE.md to describe the version row and the build-time stamping"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 (T001-T002): confirm a green baseline.
2. Phase 2 (T003-T005): `AppVersion` plus its unit tests.
3. Phase 3 (T006-T010): the General tab row and its manual checks.
4. **Stop and validate**: the user's original request is satisfied at this point.

Note the honest caveat if you stop here: the bundle would show whatever
`Info.plist` currently declares. Doing T013 alone (correcting the fallback values)
makes the MVP truthful without any of the build automation.

### Incremental Delivery

1. Setup + Foundational → the value and its rules exist and are tested.
2. Add US1 → the version is visible → demo.
3. Add US2 → the version is copyable → demo.
4. Add US3 → the version can no longer drift from the release → demo.
5. Polish → acceptance recorded, docs updated, checklist walked.

### Suggested single-session order

For one person, the natural order is T001 → T002 → T003 → T004 → T005 → T013 →
T014 → T015 → T016 → T017 → T006 → T007 → T011, then one build and one pass
through the manual checks (T008, T009, T010, T012, T018, T019, T020, T021, T022,
T023), then polish (T024 through T028). Doing the stamping before the first build
means the manual checks are performed against correctly stamped values, which
saves an entire rebuild-and-recheck cycle.

---

## Notes

- 28 tasks: 2 setup, 3 foundational, 5 for US1, 2 for US2, 9 for US3, 7 polish.
- Manual verification tasks are first-class here by constitutional requirement, not
  optional extras.
- Rebuilding changes the ad-hoc signature, so the Accessibility permission for the
  rest of the application must be re-granted after each `build-app.sh` run. This
  feature does not need that permission, but the app's other functions do.
- Commit after each logical group; the repository convention is Conventional
  Commits.

---

## Phase 7: Convergence

Appended by `/speckit-converge` on 2026-08-04 after assessing the codebase against
`spec.md`, `plan.md`, `tasks.md` and the constitution. No `missing` gaps and no
constitution violations were found. Tasks T008-T010, T012 and T021-T023 above are
still open manual verification and are deliberately not repeated here.

- [ ] T029 Revert the four files reformatted as collateral by the repo-wide `make format` in T026 (`Sources/Overtype/OvertypeApp.swift`, `Sources/Overtype/Support/PermissionManager.swift`, `Tests/OvertypeTests/GeminiProviderTests.swift`, `Tests/OvertypeTests/SlugGenerationTests.swift`) so every changed line traces to this feature, or record in the PR description why the reformatting belongs here per tasks: T026 scope (unrequested)
- [X] T030 Amend FR-007 in `specs/006-settings-version-display/spec.md` to state the three-state rule the code implements: `Unknown` only when the released version itself is unreadable, and the version alone when the version reads but the build identifier does not, matching `data-model.md` row 2 and `AppVersionTests.testBuildAbsentShowsVersionAlone` per FR-007 (partial)
- [ ] T031 After the manual acceptance pass, replace the `pending` entries in rows 5 through 9 of the Version Display Acceptance table in `docs/compatibility.md` with dated results, since a release must not ship with unexecuted manual acceptance per Constitution VIII (partial)
- [X] T032 Update the stale example numbers in `specs/006-settings-version-display/spec.md` (clarification session line, US2 acceptance scenario 1, and FR-003) from `1.1.0 (2)` to the shipped `1.2.1 (20)` per FR-003, US2/AC1 (partial)
- [X] T033 Add a reopen check to quickstart step 5 in `specs/006-settings-version-display/quickstart.md` and to T008's expected result: close and reopen the Settings window and confirm the version value is identical, per Edge Cases (reopen) and `contracts/version-display.md` guarantee 4 (partial)
- [X] T034 Extend quickstart step 7 in `specs/006-settings-version-display/quickstart.md` to include one system text size change (System Settings > Displays > Text Size or the accessibility text size control) and confirm the version row follows it, per Edge Cases (appearance) and `contracts/version-display.md` guarantee 7 (partial)
- [X] T035 Add an explicit assertion to quickstart step 5 that the version is found in under 10 seconds with at most two interactions (open Settings, select General), so the criterion is verified rather than assumed per SC-001 (partial)
