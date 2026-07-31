# Tasks: Overtype (Reword)

**Input**: Design documents from `/specs/001-overtype/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/protocols.md`

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [ ] T001 Initialize SPM project with executable target `Reword` and test target in `Package.swift`
- [ ] T002 Create `scripts/build-app.sh` for app bundle generation and ad-hoc signing
- [ ] T003 [P] Create `Sources/Reword/Resources/Info.plist` setting `LSUIElement` to true

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 [P] Create data models in `Sources/Reword/Config/AppConfig.swift`
- [ ] T005 Create `Sources/Reword/Config/DefaultConfig.swift` with initial JSON layout
- [ ] T006 Implement file watching configuration loader in `Sources/Reword/Config/ConfigStore.swift`
- [ ] T007 [P] Implement `Sources/Reword/Security/KeychainStore.swift` for API keys
- [ ] T008 [P] Implement `Sources/Reword/Support/Logger.swift`
- [ ] T009 Implement Accessibility helpers in `Sources/Reword/Support/AXHelpers.swift`
- [ ] T010 Implement `Sources/Reword/Core/SelectionReader.swift` (AXUIElement logic)
- [ ] T011 Implement `Sources/Reword/Core/TextWriter.swift` (CGEvent typing logic)
- [ ] T012 Implement `Sources/Reword/Core/ResponseSanitizer.swift` (formatting cleanup)
- [ ] T013 Implement `Sources/Reword/Core/HotkeyManager.swift` using `KeyboardShortcuts`
- [ ] T014 [P] Create `Sources/Reword/UI/FeedbackPresenter.swift` and `Sources/Reword/UI/HUDPanel.swift`
- [ ] T015 Create `Sources/Reword/UI/PermissionWindow.swift` for Accessibility grants
- [ ] T016 Create app entry in `Sources/Reword/RewordApp.swift` and `Sources/Reword/AppDelegate.swift`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Apply Grammar Correction in Chat Applications (Priority: P1) 🎯 MVP

**Goal**: Read text from complex apps (MS Teams), apply OpenAI grammar correction, and write back without clipboard.

**Independent Test**: Trigger shortcut in MS Teams; verify text replaces safely and clipboard is untouched.

### Tests for User Story 1

- [ ] T017 [P] [US1] Create unit tests in `Tests/RewordTests/ResponseSanitizerTests.swift`
- [ ] T018 [P] [US1] Create unit tests in `Tests/RewordTests/ConfigStoreTests.swift`
- [ ] T019 [P] [US1] Create unit tests in `Tests/RewordTests/PromptTemplateTests.swift`

### Implementation for User Story 1

- [ ] T020 [P] [US1] Create AIProvider protocols in `Sources/Reword/Providers/AIProvider.swift`
- [ ] T021 [US1] Implement `Sources/Reword/Providers/OpenAICompatibleProvider.swift`
- [ ] T022 [US1] Implement `Sources/Reword/Providers/ProviderRegistry.swift`
- [ ] T023 [US1] Implement `Sources/Reword/Core/ActionEngine.swift` tying reader, provider, and writer
- [ ] T024 [US1] Connect `ActionEngine` execution to `HotkeyManager` callbacks
- [ ] T025 [US1] Create `Sources/Reword/UI/Settings/SettingsWindow.swift` and `Sources/Reword/UI/Settings/GeneralTab.swift`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Adjust Tone to Formal (Priority: P2)

**Goal**: Support multiple actions, user prompt templating, and Anthropic provider.

**Independent Test**: Map "Make Formal" to a shortcut, verify Anthropic provider works and tone changes accurately.

### Implementation for User Story 2

- [ ] T026 [P] [US2] Create `Sources/Reword/UI/Settings/ActionsTab.swift` to manage ActionConfig mapping
- [ ] T027 [US2] Implement `Sources/Reword/Providers/AnthropicProvider.swift`
- [ ] T028 [US2] Update `Sources/Reword/Providers/ProviderRegistry.swift` to register AnthropicProvider
- [ ] T029 [US2] Create `Sources/Reword/UI/Settings/ProvidersTab.swift` to manage multiple ProviderConfigs and Keychain

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Use Local AI Model for Privacy (Priority: P3)

**Goal**: Fully local privacy-preserving transformations using Ollama without external network calls.

**Independent Test**: Connect to a local Ollama endpoint without keys and verify text replaces normally.

### Implementation for User Story 3

- [ ] T030 [P] [US3] Implement `Sources/Reword/Providers/OllamaProvider.swift`
- [ ] T031 [US3] Update `Sources/Reword/Providers/ProviderRegistry.swift` to register OllamaProvider
- [ ] T032 [US3] Create `Sources/Reword/UI/Settings/DiagnosticsTab.swift` to audit requests and inspect AX elements

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T033 [P] Documentation updates in `README.md`
- [ ] T034 [P] Documentation updates in `docs/privacy.md` and `docs/compatibility.md`
- [ ] T035 Verify compliance with all constraints (run quickstart.md validation)

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
