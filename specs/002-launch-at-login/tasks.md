---
description: "Task list for Launch at Login feature implementation"
---

# Tasks: Launch at Login

**Input**: Design documents from `/specs/002-launch-at-login/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Because this feature interacts with a system boundary (`SMAppService`), automated unit testing is explicitly forbidden by Constitution Principle VIII (Verification Discipline). All testing must be manual according to the quickstart guide.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Verify project builds cleanly via `make build` before starting

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

- [x] T002 Increment minor version (`CFBundleShortVersionString` to next minor, `CFBundleVersion` + 1) in `Sources/Overtype/Resources/Info.plist`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Enable Launch at Login (Priority: P1) 🎯 MVP

**Goal**: Users can configure Overtype to automatically launch when they log into their Mac.

**Independent Test**: Enable the option in Settings, reboot, and verify the app runs.

### Implementation for User Story 1

- [x] T003 [US1] Create `LaunchAtLoginManager` in `Sources/Overtype/Support/LaunchAtLoginManager.swift` wrapping `SMAppService.mainApp.status` with `register()` logic and error handling.
- [x] T004 [US1] Add "Launch at Login" Checkbox to `Sources/Overtype/UI/SettingsView.swift` bound to `LaunchAtLoginManager.isEnabled`.

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Disable Launch at Login (Priority: P1)

**Goal**: Users can stop Overtype from launching automatically if they prefer to start it manually.

**Independent Test**: Disable the option in Settings, reboot, and verify the app does not run.

### Implementation for User Story 2

- [x] T005 [US2] Update `LaunchAtLoginManager` in `Sources/Overtype/Support/LaunchAtLoginManager.swift` to handle `unregister()` logic when the toggle is turned off.

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T006 Run all scenarios in `specs/002-launch-at-login/quickstart.md` manually to validate `SMAppService` and version increment behavior.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (US1 → US2)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2)
- **User Story 2 (P1)**: Depends on `LaunchAtLoginManager` scaffolding created in US1 (T003).

### Within Each User Story

- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- T002 (Foundational) can run independently.
- T003 and T004 can be parallelized if the interface of `LaunchAtLoginManager` is agreed upon.

---

## Parallel Example: User Story 1

```bash
# Developer A focuses on the SMAppService wrapper logic:
Task: "Create LaunchAtLoginManager in Sources/Overtype/Support/LaunchAtLoginManager.swift"

# Developer B focuses on the SwiftUI settings UI:
Task: "Add 'Launch at Login' Checkbox to Sources/Overtype/UI/SettingsView.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (Enable) → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 (Disable) → Test independently → Deploy/Demo
4. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
