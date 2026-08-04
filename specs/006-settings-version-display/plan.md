# Implementation Plan: Application Version in Settings General Tab

**Branch**: `006-settings-version-display` | **Date**: 2026-08-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-settings-version-display/spec.md`

## Summary

Show the running application's version on the Settings > General tab as a
read-only row labelled `Version` with the value `<short version> (<build>)`, for
example `1.2.1 (20)`, falling back to `Unknown` when the value cannot be read.

The value is read from the running bundle's own metadata
(`CFBundleShortVersionString` / `CFBundleVersion`). Because the clarification
session put version accuracy in scope (FR-002a, FR-002b, SC-007), the app bundle
build script also stamps those two keys at build time: the released version comes
from the git tag, the build identifier from the commit count, and an unstamped
local build falls back to the values checked into `Info.plist`.

Formatting is pure logic in a new `AppVersion` type and is unit-tested. Reading
the bundle, rendering the row, and the shell stamping are system-boundary work,
verified by the manual procedure in [quickstart.md](./quickstart.md).

**Correction to a spec-stage assumption**: the spec and its checklist recorded the
newest release as `1.1.0`. The actual newest tag in this repository is **`v1.2.1`**
(`1.1.0` was the version of the archive Spec Kit extension, not the app), while
`Sources/Overtype/Resources/Info.plist` still declares `1.1` build `2`. The drift
this feature closes is therefore larger than the spec estimated. Nothing in the
spec's requirements changes; only the concrete numbers used below.

## Technical Context

**Language/Version**: Swift 5.9

**Primary Dependencies**: SwiftUI, Foundation (`Bundle`). No new package
dependency. `/usr/libexec/PlistBuddy` (part of macOS) is used by the build script.

**Storage**: None. The version is read at display time and never persisted.
`config.json` is untouched (FR-009).

**Testing**: XCTest via `swift test`. New `AppVersionTests` covers the pure
formatting rules. Bundle reading, the SwiftUI row, and the build script are
covered by the manual procedure, per Constitution Principle VIII.

**Target Platform**: macOS 13+, menu bar accessory (`LSUIElement`), unsandboxed.

**Project Type**: Native macOS desktop application, built with Swift Package
Manager and packaged into an `.app` bundle by `scripts/build-app.sh`.

**Performance Goals**: Reading two dictionary keys once per view render; no
measurable cost. Opening the General tab must stay instant (SC-001).

**Constraints**: Zero network activity (FR-008, SC-004). Read-only, no
participation in the tab's save action (FR-004). The row must not break the
existing General tab layout or behaviour (FR-010, SC-006).

**Scale/Scope**: One new source file, one modified view, one modified plist, one
modified build script, one modified workflow step, one new test file. No
NEEDS CLARIFICATION items remain.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Assessment |
|-----------|------------|
| **I. Clipboard Isolation** | PASS. No `NSPasteboard` use is added; `rg NSPasteboard Sources/` currently returns nothing and must still return nothing. FR-005 is satisfied by `.textSelection(.enabled)`, which lets the *system* copy on an explicit user command, exactly as the existing Settings text fields already do. The application never reads or writes the pasteboard itself, and nothing in the text transformation pipeline is touched. |
| **II. Non-Destructive by Default** | PASS. Display-only. No selection is read or written, no user data is modified, and the row cannot be edited or saved (FR-004, FR-009). |
| **III. Evidence Over Assumption** | PASS. The claim "the bundle reports the version at runtime" is verified empirically by the manual procedure (build the bundle, read the stamped plist, launch, read the tab), not assumed from documentation. No Accessibility or synthetic-event behaviour is involved, so no new boundary workaround comment is required. |
| **IV. Configuration Over Code** | PASS. No new action, provider or configuration field. The feature adds no code that a future automation would have to change. |
| **V. Privacy and Secret Handling** | PASS. No network endpoint is contacted (FR-008): no update check, no release-notes fetch, no telemetry. The version is not user content and is not logged. No secret is involved. |
| **VI. No Silent Failure** | PASS. Missing or unreadable metadata renders the explicit `Unknown` placeholder rather than a blank or a zero (FR-007, SC-005). There is no failure path that leaves the user uncertain. |
| **VII. Native Stack, Minimal Dependencies** | PASS. SwiftUI and Foundation only; no third-party dependency added. No force unwrapping: the two Info dictionary lookups use optional binding. PlistBuddy is a macOS system tool used by a build script, not an application dependency. |
| **VIII. Verification Discipline** | PASS. Pure logic (the formatting rules, including the fallbacks) is unit-tested. Bundle reading, UI rendering and shell stamping are not mocked; they are exercised by the written manual procedure and the result recorded in `docs/compatibility.md` before release. |

Additional governance note: this change also touches release plumbing
(`scripts/build-app.sh`, `.github/workflows/release.yml`). That is permitted work
under the workflow rules ("code written outside this flow is limited to build
scripts and documentation"), and here it is inside the flow because the
clarification session brought it into the spec as FR-002a/FR-002b.

**Result: no violations. Complexity Tracking section is therefore omitted.**

## Project Structure

### Documentation (this feature)

```text
specs/006-settings-version-display/
├── plan.md              # This file
├── research.md          # Phase 0 output: decisions and rejected alternatives
├── data-model.md        # Phase 1 output: AppVersion value and formatting rules
├── quickstart.md        # Phase 1 output: manual acceptance procedure
├── contracts/
│   ├── version-display.md         # UI contract for the General tab row
│   └── build-version-stamping.md  # Contract for the build-time stamping step
├── checklists/
│   └── requirements.md  # From /speckit-specify, re-validated by /speckit-clarify
└── tasks.md             # Created later by /speckit-tasks
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Support/
│   └── AppVersion.swift            # NEW: pure formatting + bundle reader
├── UI/Settings/
│   └── GeneralTab.swift            # MODIFIED: read-only "Version" row at the end
└── Resources/
    └── Info.plist                  # MODIFIED: corrected fallback version values

Tests/OvertypeTests/
└── AppVersionTests.swift           # NEW: unit tests for the formatting rules

scripts/
└── build-app.sh                    # MODIFIED: stamp version/build into the bundle
                                    #           copy of Info.plist before codesign

.github/workflows/
└── release.yml                     # MODIFIED: pass the tag version to the build

docs/
└── compatibility.md                # MODIFIED: record the manual acceptance result
```

**Structure Decision**: The existing single-package layout is kept unchanged. The
new type goes in `Sources/Overtype/Support/`, alongside the other small
non-pipeline helpers (`Logger.swift`, `AXHelpers.swift`, `PermissionManager.swift`),
because it is a self-contained utility with no dependency on config, providers or
the action pipeline. The view change is confined to `GeneralTab.swift`; no change
to `SettingsViewModel` is made, since the version is not draft state and must not
participate in saving (FR-004).

## Phase 0 output

See [research.md](./research.md). Seven decisions recorded, covering the runtime
source of the version, the exact formatting and fallback rules, the UI placement,
the build-time stamping mechanism, the checked-in fallback values, the release
workflow change, and the test boundary. No unresolved unknowns remain.

## Phase 1 output

- [data-model.md](./data-model.md) — the `AppVersion` value, its two fields, the
  formatting decision table, and the requirement traceability map.
- [contracts/version-display.md](./contracts/version-display.md) — what the
  General tab row must show, in every input state, and what it must not do.
- [contracts/build-version-stamping.md](./contracts/build-version-stamping.md) —
  inputs, precedence, outputs and invariants of the stamping step, including the
  ordering constraint against code signing.
- [quickstart.md](./quickstart.md) — the runnable validation and manual acceptance
  procedure, with the exact commands and expected results.

## Post-Design Constitution Re-Check

Re-evaluated after the Phase 1 artifacts were written. All eight principles still
PASS, with two points worth stating explicitly because they are the only places
the design could have drifted:

1. **Stamping must happen before code signing.** `codesign` seals `Info.plist`;
   editing it afterwards invalidates the signature and macOS refuses to launch the
   bundle. The contract fixes the order (copy plist → stamp → copy resources →
   sign) and the quickstart verifies it with `codesign --verify`. This is a real
   platform constraint, recorded as such rather than assumed to be harmless.
2. **The stamping step must never write to the tracked `Info.plist`.** It edits
   only the copy inside `Overtype.app`. `git status` staying clean after a build
   is an explicit check in the quickstart, so a local build cannot silently
   rewrite the repository's fallback values.

No new dependency, no clipboard use, no network call, no persisted data, and no
force unwrapping were introduced by the design.
