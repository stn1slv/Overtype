# Implementation Plan: Launch at Login

**Branch**: `[002-launch-at-login]` | **Date**: 2026-08-01 | **Spec**: [spec.md](file:///Users/Stanislav_Deviatov/src/github/overtype/specs/002-launch-at-login/spec.md)

**Input**: Feature specification from `/specs/002-launch-at-login/spec.md`

## Summary

Add a "Launch at Login" checkbox to the app's settings using macOS native `SMAppService` to manage the login item status. Additionally, increment the application's minor version to reflect the feature addition.

## Technical Context

**Language/Version**: Swift 5.9

**Primary Dependencies**: SwiftUI, `ServiceManagement` framework (`SMAppService`)

**Storage**: OS-level login item state (managed by macOS, no custom disk storage needed).

**Testing**: Manual acceptance procedure (system boundary code).

**Target Platform**: macOS 13+

**Project Type**: macOS menu bar utility

**Performance Goals**: N/A (UI operation)

**Constraints**: Errors registering the service must be caught and displayed to the user; state must reflect actual macOS login item state.

**Scale/Scope**: Single UI toggle and minor plist modifications.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Clipboard Isolation**: N/A
- **II. Non-Destructive by Default**: N/A
- **III. Evidence Over Assumption**: The plan uses `SMAppService.mainApp` as Apple recommends for macOS 13+.
- **IV. Configuration Over Code**: N/A (this is an app-level setting, not a text transformation configuration).
- **V. Privacy and Secret Handling**: N/A
- **VI. No Silent Failure**: The UI will report an error if `register()` or `unregister()` throws an error, and the checkbox state will be restored to reflect the OS reality.
- **VII. Native Stack, Minimal Dependencies**: Uses Apple's native `ServiceManagement` framework, no third-party libraries.
- **VIII. Verification Discipline**: Because `SMAppService` is a system boundary, it will be tested manually rather than mocked in unit tests.

## Project Structure

### Documentation (this feature)

```text
specs/002-launch-at-login/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Resources/
│   └── Info.plist       # Will be modified to increment minor version
├── UI/
│   └── SettingsView.swift # Will be modified to add the Launch at Login checkbox
└── Support/
    └── LaunchAtLoginManager.swift # New file for encapsulating SMAppService logic
```

**Structure Decision**: The project is a single Swift package. The new logic interacts with the system boundary, so we will place the `SMAppService` interaction in a manager class under `Support/` and bind it to the SwiftUI view in `UI/`. The version bump will happen in `Resources/Info.plist`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*(No violations)*
