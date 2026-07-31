# Tasks: Overtype (Overtype)

**Input**: Design documents from `/specs/001-overtype/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/protocols.md`

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Initialize SPM project with executable target `Overtype` and test target in `Package.swift`
- [x] T002 Create `scripts/build-app.sh` for app bundle generation and ad-hoc signing
- [x] T003 [P] Create `Sources/Overtype/Resources/Info.plist` setting `LSUIElement` to true

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 [P] Create data models in `Sources/Overtype/Config/AppConfig.swift`
- [x] T005 Create `Sources/Overtype/Config/DefaultConfig.swift` with initial JSON layout
- [x] T006 Implement file watching configuration loader in `Sources/Overtype/Config/ConfigStore.swift`
- [x] T007 [P] Implement `Sources/Overtype/Security/KeychainStore.swift` for API keys
- [x] T008 [P] Implement `Sources/Overtype/Support/Logger.swift`
- [x] T009 Implement Accessibility helpers in `Sources/Overtype/Support/AXHelpers.swift`
- [x] T010 Implement `Sources/Overtype/Core/SelectionReader.swift` (AXUIElement logic)
- [x] T011 Implement `Sources/Overtype/Core/TextWriter.swift` (CGEvent typing logic)
- [x] T012 Implement `Sources/Overtype/Core/ResponseSanitizer.swift` (formatting cleanup)
- [x] T013 Implement `Sources/Overtype/Core/HotkeyManager.swift` using `KeyboardShortcuts`
- [x] T014 [P] Create `Sources/Overtype/UI/FeedbackPresenter.swift` and `Sources/Overtype/UI/HUDPanel.swift`
- [x] T015 Create `Sources/Overtype/UI/PermissionWindow.swift` for Accessibility grants
- [x] T016 Create app entry in `Sources/Overtype/OvertypeApp.swift` and `Sources/Overtype/AppDelegate.swift`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Apply Grammar Correction in Chat Applications (Priority: P1) 🎯 MVP

**Goal**: Read text from complex apps (MS Teams), apply OpenAI grammar correction, and write back without clipboard.

**Independent Test**: Trigger shortcut in MS Teams; verify text replaces safely and clipboard is untouched.

### Tests for User Story 1

- [x] T017 [P] [US1] Create unit tests in `Tests/OvertypeTests/ResponseSanitizerTests.swift`
- [x] T018 [P] [US1] Create unit tests in `Tests/OvertypeTests/ConfigStoreTests.swift`
- [x] T019 [P] [US1] Create unit tests in `Tests/OvertypeTests/PromptTemplateTests.swift`

### Implementation for User Story 1

- [x] T020 [P] [US1] Create AIProvider protocols in `Sources/Overtype/Providers/AIProvider.swift`
- [x] T021 [US1] Implement `Sources/Overtype/Providers/OpenAICompatibleProvider.swift`
- [x] T022 [US1] Implement `Sources/Overtype/Providers/ProviderRegistry.swift`
- [x] T023 [US1] Implement `Sources/Overtype/Core/ActionEngine.swift` tying reader, provider, and writer
- [x] T024 [US1] Connect `ActionEngine` execution to `HotkeyManager` callbacks
- [x] T025 [US1] Create `Sources/Overtype/UI/Settings/SettingsWindow.swift` and `Sources/Overtype/UI/Settings/GeneralTab.swift`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Adjust Tone to Formal (Priority: P2)

**Goal**: Support multiple actions, user prompt templating, and Anthropic provider.

**Independent Test**: Map "Make Formal" to a shortcut, verify Anthropic provider works and tone changes accurately.

### Tests for User Story 2 & 3
 
- [-] T026 [US2] Create unit tests for Anthropic payload formatting
- [-] T030 [US3] Create unit tests for Ollama payload formatting
 
### Implementation for User Story 2 (Anthropic)
 
- [-] T027 [US2] Implement `Sources/Overtype/Providers/AnthropicProvider.swift`
- [-] T028 [US2] Update `ProviderRegistry.swift` to initialize `AnthropicProvider`
- [-] T029 [US2] Update Settings UI to support Anthropic API Key input
 
### Implementation for User Story 3 (Ollama)
 
- [-] T031 [US3] Implement `Sources/Overtype/Providers/OllamaProvider.swift`
- [-] T032 [US3] Update `ProviderRegistry.swift` to initialize `OllamaProvider`Configs and Keychain

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Use Local AI Model for Privacy (Priority: P3)

**Goal**: Fully local privacy-preserving transformations using Ollama without external network calls.

**Independent Test**: Connect to a local Ollama endpoint without keys and verify text replaces normally.

### Implementation for User Story 3

- [-] T030 [P] [US3] Implement `Sources/Overtype/Providers/OllamaProvider.swift`
- [-] T031 [US3] Update `Sources/Overtype/Providers/ProviderRegistry.swift` to register OllamaProvider
- [-] T032 [US3] Create `Sources/Overtype/UI/Settings/DiagnosticsTab.swift` to audit requests and inspect AX elements

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T033 [P] Documentation updates in `README.md`
- [x] T034 [P] Documentation updates in `docs/privacy.md` and `docs/compatibility.md`
- [x] T035 Verify compliance with all constraints (run quickstart.md validation)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2)
- **User Story 2 (P2)**: Integrates with general UI components from US1
- **User Story 3 (P3)**: Integrates with provider and UI components from US1 and US2

### Parallel Opportunities

- Foundation components (Models, Stores, UI stubs, Helpers) can be built in parallel.
- Unit tests can run entirely in parallel with foundational execution.
- Documentation updates can run in parallel with final UI tweaks.

## Phase 7: Convergence

- [ ] T036 Add global NSEvent monitor for Escape key to cancel in-flight tasks per FR-009 (missing)
