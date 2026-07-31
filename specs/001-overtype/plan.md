# Implementation Plan: Overtype (Overtype)

**Branch**: `001-overtype` | **Date**: 2026-07-31 | **Spec**: [spec.md](file:///Users/Stanislav_Deviatov/src/github/overtype/specs/001-overtype/spec.md)

**Input**: Feature specification from `/specs/001-overtype/spec.md`

## Summary

Build a native macOS menu bar application that transforms user-selected text using AI without interacting with the system clipboard. The application relies entirely on Accessibility API and synthetic keyboard events for its core loop and is extensible via configuration rather than code.

## Technical Context

**Language/Version**: Swift 5.9+

**Primary Dependencies**: Native frameworks only (AppKit, SwiftUI, Security Framework, Accessibility API, URLSession). Optionally: `KeyboardShortcuts` SPM package for hotkey registration.

**Storage**: `config.json` via file system (`Codable`), API Keys via macOS Keychain.

**Testing**: XCTest for pure logic. Manual validation for system boundaries (Accessibility/CGEvent).

**Target Platform**: macOS 13 Ventura+

**Project Type**: macOS menu bar utility (`LSUIElement` app)

**Performance Goals**: AI text replacement workflow < 3 seconds total latency; instant feedback via HUD.

**Constraints**: Unsandboxed, zero use of `NSPasteboard`, no silent failures, no data logging (unless explicitly debug mode).

**Scale/Scope**: Local background utility application.

## Constitution Check

*GATE: Passed*

- **I. Clipboard Isolation**: Verified. Implementation relies strictly on Accessibility API for reading and `CGEvent` for writing.
- **II. Non-Destructive by Default**: Verified. Operations cancel on focus loss, and the original text is preserved on error.
- **IV. Configuration Over Code**: Verified. Actions and providers are loaded dynamically from JSON config.
- **V. Privacy and Secret Handling**: Verified. Network calls are restricted to the selected provider using `URLSession`. API keys live in the Keychain.
- **VII. Native Stack, Minimal Dependencies**: Verified. No third-party network libraries or heavy wrappers.

## Project Structure

### Documentation (this feature)

```text
specs/001-overtype/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (to be created by /speckit-tasks)
```

### Source Code (repository root)

```text
Overtype/
├── Package.swift (or Overtype.xcodeproj)
├── README.md
├── Sources/Overtype/
│   ├── OvertypeApp.swift
│   ├── AppDelegate.swift
│   ├── Core/
│   ├── Providers/
│   ├── Config/
│   ├── Security/
│   ├── UI/
│   ├── Support/
│   └── Resources/
├── Tests/OvertypeTests/
└── scripts/
    └── build-app.sh
```

**Structure Decision**: The project uses a single Swift target layout typical for SPM executables or standard Xcode applications, logically separated into Core, Providers, Config, Security, and UI domains.
