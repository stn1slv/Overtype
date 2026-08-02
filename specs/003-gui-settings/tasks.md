# Tasks: GUI Configuration Settings

**Input**: Design documents from `/specs/003-gui-settings/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/config-schema.json

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: `Sources/`, `Tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic validation

- [x] T001 Verify clean build status and run existing tests via `make test`
- [x] T002 Verify KeyboardShortcuts framework package dependency is successfully resolved in `Package.swift`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core model serialization, state management, and validation logic that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Create the shared view model `SettingsViewModel.swift` at `Sources/Overtype/UI/Settings/SettingsViewModel.swift` that handles configuration loading, draft states, and auto-saving
- [x] T004 Implement helper slug-generation and deduplication functions inside `Sources/Overtype/UI/Settings/SettingsViewModel.swift` or a utility extension
- [x] T005 [P] Write unit tests in `Tests/OvertypeTests/SlugGenerationTests.swift` to verify slug generation and collision numeric suffixes
- [x] T006 [P] Write unit tests in `Tests/OvertypeTests/AppConfigTests.swift` to verify model encoding/decoding constraints match the JSON schema contract

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Manage AI Providers and Credentials (Priority: P1) 🎯 MVP

**Goal**: Allow users to add, edit, and delete OpenAI-compatible providers and store API keys securely in the Keychain via the GUI.

**Independent Test**: Create a provider in the Settings GUI, verify it is saved to `config.json` with a generated ID and no plain-text API key, and verify the API key is successfully retrievable from the macOS Keychain.

### Implementation for User Story 1

- [x] T007 [US1] Create the provider detail form view `ProvidersTabDetailView` in `Sources/Overtype/UI/Settings/ProvidersTab.swift` to capture ID, URL, model, timeout, and API key
- [x] T008 [US1] Create the list view `ProvidersTab` in `Sources/Overtype/UI/Settings/ProvidersTab.swift` to display configured providers and navigation to edit/add flows
- [x] T009 [US1] Implement secure API key Keychain saving and metadata JSON persistence actions inside `Sources/Overtype/UI/Settings/SettingsViewModel.swift`
- [x] T010 [US1] Integrate `ProvidersTab` into `Sources/Overtype/UI/Settings/SettingsWindow.swift` to replace the "Providers Configuration (Coming Soon)" placeholder

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently.

---

## Phase 4: User Story 2 - Manage Actions/Automations and Shortcuts (Priority: P1)

**Goal**: Create, edit, and delete text automations and assign hotkeys via the settings UI.

**Independent Test**: Create a custom action (e.g. "Proofread Email"), assign a hotkey, save it, and verify that pressing the hotkey triggers the action successfully.

### Implementation for User Story 2

- [x] T011 [US2] Create the action detail form view `ActionsTabDetailView` in `Sources/Overtype/UI/Settings/ActionsTab.swift` to configure titles, prompts, write strategy, and parameters
- [x] T012 [US2] Integrate `KeyboardShortcuts.Recorder` into `ActionsTabDetailView` in `Sources/Overtype/UI/Settings/ActionsTab.swift` to capture key codes and modifiers
- [x] T013 [US2] Create the list view `ActionsTab` in `Sources/Overtype/UI/Settings/ActionsTab.swift` displaying actions, hotkeys, and edit/add options
- [x] T014 [US2] Implement hotkey collision checking and validation logic in `Sources/Overtype/UI/Settings/SettingsViewModel.swift`
- [x] T015 [US2] Implement action persistence and active HotkeyManager reloading in `Sources/Overtype/UI/Settings/SettingsViewModel.swift`
- [x] T016 [US2] Integrate `ActionsTab` into `Sources/Overtype/UI/Settings/SettingsWindow.swift` to replace the "Actions Configuration (Coming Soon)" placeholder

**Checkpoint**: At this point, User Stories 1 and 2 should both work independently.

---

## Phase 5: User Story 3 - Adjust General Preferences and Typing Cadence (Priority: P2)

**Goal**: Allow users to configure global application behaviors and manage application-specific overrides via the GUI.

**Independent Test**: Modify the speed multiplier or add an override for an application, save it, and verify the typing simulation cadence changes instantly.

### Implementation for User Story 3

- [x] T017 [US3] Refactor `Sources/Overtype/UI/Settings/GeneralTab.swift` to bind global preferences (typing speed multiplier, HUD visibility) to the shared `SettingsViewModel`
- [x] T018 [US3] Implement a list-based editor for per-application typing overrides inside `Sources/Overtype/UI/Settings/GeneralTab.swift`
- [x] T019 [US3] Implement the validation and serialization logic for per-application overrides in `Sources/Overtype/UI/Settings/SettingsViewModel.swift`

**Checkpoint**: All user stories should now be independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Refactoring, quality gates check, and manual documentation updates

- [x] T020 Run linting and formatting verification using `make lint` and `make format`
- [x] T021 Update `README.md` to reference settings management through the newly implemented settings window GUI
- [x] T022 Validate the entire setup by manually running through scenarios defined in `specs/003-gui-settings/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories.
- **User Stories (Phase 3+)**: All depend on Foundational phase completion.
  - User Story 1 (P1 - MVP) and User Story 2 (P1) are both P1 but independent; they can be developed in parallel once Phase 2 is complete.
  - User Story 3 (P2) can be worked on after Phase 2 is complete, but relies on settings view model scaffolding.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Parallel Opportunities

- Unit tests tasks **T005** and **T006** can be run in parallel.
- User Story 1 implementation (**T007**, **T008**, **T009**) and User Story 2 implementation (**T011**, **T012**, **T013**) can be worked on in parallel by different developers.
- Polish tasks **T020** and **T021** can run in parallel.

---

## Parallel Example: User Story 1 & 2

```bash
# Developer A builds Provider views:
Task: "Create the provider detail form view ProvidersTabDetailView in Sources/Overtype/UI/Settings/ProvidersTab.swift"

# Developer B builds Action views:
Task: "Create the action detail form view ActionsTabDetailView in Sources/Overtype/UI/Settings/ActionsTab.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (requires writing slug logic and unit tests).
3. Complete Phase 3: User Story 1 (Providers GUI).
4. **STOP and VALIDATE**: Verify that providers can be created/edited and keys save to the Keychain correctly.

### Incremental Delivery

1. Complete Setup + Foundational -> Foundation ready.
2. Add User Story 1 (Providers Tab) -> Test independently -> Verify MVP.
3. Add User Story 2 (Actions Tab) -> Test independently.
4. Add User Story 3 (General app overrides) -> Test overrides dynamically.
5. Apply Polish (linter checks, readme updates, quickstart run).
