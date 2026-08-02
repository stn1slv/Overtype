# Implementation Plan: GUI Configuration Settings

**Branch**: `003-gui-settings` | **Date**: August 2, 2026 | **Spec**: [spec.md](file:///Users/Stanislav_Deviatov/src/github/overtype/specs/003-gui-settings/spec.md)

**Input**: Feature specification from `/specs/003-gui-settings/spec.md`

## Summary

This feature replaces the need for manual file-editing of `config.json` by implementing a native macOS GUI settings window built in SwiftUI. The settings interface allows users to configure global preferences, manage OpenAI-compatible AI providers, input API keys securely into the macOS Keychain, and dynamically add/edit text actions with global hotkeys.

The technical approach involves:
- Refactoring `SettingsWindow` to implement three fully functional tabs: **General**, **Providers**, and **Actions**.
- Creating a `SettingsViewModel` to manage editable draft states, perform form validations (e.g. slug-based id generation, shortcut conflict checking), and execute atomic saves to `config.json` via `ConfigStore`.
- Supporting dynamic hotkey updates via the `KeyboardShortcuts` framework (using `KeyboardShortcuts.Recorder` views and mapping recorded shortcuts back to `ActionShortcut` representations).
- Ensuring Keychain storage calls for API keys and verifying that no secret values leak into `config.json` or debug logs.

## Technical Context

**Language/Version**: Swift 5.9 (macOS 13+ SDK)

**Primary Dependencies**: KeyboardShortcuts (1.15.0), SwiftUI

**Storage**: Local `config.json` in Application Support + macOS Keychain

**Testing**: XCTest / native Swift Testing

**Target Platform**: macOS 13+ (Ventura)

**Project Type**: Desktop Application (unsandboxed menu bar accessory)

**Performance Goals**: GUI interactions are instant. Writing configuration and re-registering hotkeys takes <100ms.

**Constraints**: Clipboard isolation (no usage of `NSPasteboard` or similar pasteboard APIs in settings/recording flows). Secrets must be kept strictly out of the config file.

**Scale/Scope**: Settings window containing 3 configuration tabs, form validations, dynamic hotkey re-registration, and Keychain reads/writes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The implementation plan is verified against the Overtype Constitution:

1. **Principle I: Clipboard Isolation (NON-NEGOTIABLE)**
   - *Check*: The settings interface does not use or interact with the system clipboard. Keyboard recording is handled using the `KeyboardShortcuts` package, which captures key events directly.
   - *Status*: PASS

2. **Principle II: Non-Destructive by Default (NON-NEGOTIABLE)**
   - *Check*: The configuration updates do not alter any in-flight AI text transformations. Saving settings writes atomically to `config.json` and updates the active memory configurations. If validation fails, the existing configuration on disk and in memory is left untouched.
   - *Status*: PASS

3. **Principle V: Privacy and Secret Handling (NON-NEGOTIABLE)**
   - *Check*: API keys entered in the Providers Tab are saved directly to the macOS Keychain using `KeychainStore`. They are never stored in the `AppConfig` struct serialized to `config.json`, nor written to logging outputs. The settings UI masks API key values.
   - *Status*: PASS

4. **Principle VI: No Silent Failure**
   - *Check*: The UI forms validate fields (e.g. valid URLs, unique hotkeys, non-empty prompts) and display inline error messages for validation failures. Failed disk writes or Keychain operations trigger user-facing alerts.
   - *Status*: PASS

5. **Principle VII: Native Stack, Minimal Dependencies**
   - *Check*: The configuration views are built purely in native SwiftUI. No new external dependencies are introduced (we leverage the pre-existing `KeyboardShortcuts` library).
   - *Status*: PASS

6. **Principle VIII: Verification Discipline**
   - *Check*: Logic for identifier slug-generation, validation rules, and configuration decoding is fully testable and will be covered by unit tests in `Tests/OvertypeTests/`.
   - *Status*: PASS

## Project Structure

### Documentation (this feature)

```text
specs/003-gui-settings/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── contracts/
    └── config-schema.json # Phase 1 output (/speckit-plan command)
```

### Source Code (repository root)

```text
Sources/
└── Overtype/
    ├── Config/
    │   ├── AppConfig.swift         # Defines configuration structs
    │   ├── ConfigStore.swift        # Manages config loading/saving
    │   └── DefaultConfig.swift      # Default fallback configuration
    ├── Core/
    │   └── HotkeyManager.swift      # Registers hotkeys with KeyboardShortcuts
    └── UI/
        └── Settings/
            ├── SettingsWindow.swift # Main window with tab selectors
            ├── GeneralTab.swift     # General preferences & overrides UI
            ├── ProvidersTab.swift   # Providers management form UI
            └── ActionsTab.swift     # Actions & hotkey recording UI

Tests/
└── OvertypeTests/
    ├── AppConfigTests.swift         # Config encoding/decoding tests
    └── SlugGenerationTests.swift    # ID generation & uniqueness tests
```

**Structure Decision**: Single project layout matching the existing Swift application folder hierarchy. Source code modifications are concentrated inside the `Sources/Overtype/UI/Settings/` folder, with model extension logic in `Sources/Overtype/Config/` and tests in `Tests/OvertypeTests/`.

## Complexity Tracking

*No constitution violations are introduced, so complexity tracking entries are not required.*
