# Implementation Plan: Reliable Selection Reading for Apps with Dormant Accessibility Trees

**Branch**: `005-teams-ax-recovery` | **Date**: 2026-08-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-teams-ax-recovery/spec.md`

## Summary

Microsoft Teams (and other lazily-initialized web-based apps) exposes no
accessibility tree after its process restarts, so `AXHelpers.getFocusedElement()`
fails instantly with `noFocusedElement`. The fix adds a bounded recovery path,
entered only when all existing lookup strategies fail: set the two assistive-client
wake-up flags on the target application (ignoring their reported error codes,
a verified quirk), apply a 2-second accessibility messaging timeout, and retry
an app-element-first lookup up to 24 times at 150 ms intervals. The recovery is
used only for the initial selection read; the pre-write context re-check keeps
today's fast, single-shot behavior. All parameters come from the recorded
2026-07-31 axprobe findings and the 2026-08-02 live diagnostic.

## Technical Context

**Language/Version**: Swift 5.9 (Swift Package Manager, no Xcode project)

**Primary Dependencies**: ApplicationServices (AX API), Cocoa; no new third-party dependencies

**Storage**: N/A (no config surface; constants in code, matching tested values)

**Testing**: XCTest for pure logic only; AX behavior verified by manual acceptance recorded in `docs/compatibility.md` (constitution Principle VIII)

**Target Platform**: macOS 13+

**Project Type**: Desktop menu bar accessory app

**Performance Goals**: Zero added latency on the fast path; recovery bounded to ~3.5 s of retries plus 2 s messaging timeout per query, always within the run's hard timeout

**Constraints**: No clipboard; non-destructive; recovery must respect Task cancellation (Escape); wake-up flags set only on the failure path (known Electron side effects)

**Scale/Scope**: One file carries the behavior change (`Sources/Overtype/Support/AXHelpers.swift`), one call site opts in (`Core/SelectionReader.swift`), plus documentation (`docs/compatibility.md`)

## Constitution Check

*GATE: evaluated against constitution v1.1.0. Result: PASS (no violations, no amendments requested).*

- **I. Clipboard Isolation**: PASS. No clipboard involvement; the change is confined to Accessibility API reads and two AX attribute writes on the target app element (wake flags), not on any text.
- **II. Non-Destructive by Default**: PASS. Recovery runs entirely during the read stage; nothing is written to the document. The pre-write context re-check intentionally does NOT use recovery, so a genuine context change still aborts fast (design decision below).
- **III. Evidence Over Assumption**: PASS. Every parameter (app-element-first, 12 x 150 ms, 2 s messaging timeout, both wake flags, ignoring their return codes) is bound to the recorded 2026-07-31 axprobe findings and the 2026-08-02 diagnostic run (documented in research.md). The ignore-error-code site and the wake-flag site carry QUIRK comments naming the behavior. `docs/compatibility.md` is updated with the dormant-tree entry.
- **IV. Configuration Over Code**: PASS (not applicable). No new automation or provider surface. Deliberately no config knobs: the values are empirically fixed, and exposing them would invite untested combinations.
- **V. Privacy and Secret Handling**: PASS. No new logging of selected text; recovery logs only attempt counts and error codes at appropriate levels.
- **VI. No Silent Failure**: PASS. All existing typed errors (`noFocusedElement`, `cannotReadSelectedText`) are preserved; recovery is bounded (max ~3.5 s of sleeps + per-query timeout) and checks `Task.checkCancellation()` every attempt, so Escape works.
- **VII. Native Stack, Minimal Dependencies**: PASS. No new dependencies. Any unavoidable CF cast keeps the existing `asElement` type-checked helper (no new force casts).
- **VIII. Verification Discipline**: PASS. The recovery is system-boundary code: no mock-based unit tests; verified by the manual acceptance procedure in quickstart.md, recorded in `docs/compatibility.md`. No new pure logic is introduced beyond trivial constants, so no new unit tests are required; existing tests must stay green.

## Design Decisions

1. **Opt-in recovery parameter, not a new default.**
   `getFocusedElement(wakeDormantTree: Bool = false)`; only
   `SelectionReader.readSelection()` passes `true`. The pre-write context
   re-check in `ActionEngine` keeps the fast single-shot behavior, because:
   (a) by write time the tree is provably warm (we just read from it), and
   (b) a genuine context change must abort quickly, not after 1.8 s of retries.
   Simpler alternative (always recover) rejected because it slows the abort
   path of Principle II's re-check.

2. **Escalation order inside recovery** (all only after strategies 1-5 fail):
   - Set `AXEnhancedUserInterface = true` on the target app element, ignoring
     the result code. QUIRK: Teams returns `.notImplemented` (-25208) yet
     honors the write (value read-back flips 0 to 1 and the tree activates;
     verified live 2026-08-02).
   - Set `AXManualAccessibility = true`, ignoring the result code. QUIRK:
     rejected by Teams (`attributeUnsupported`) but honored by Electron apps
     (VS Code, Claude desktop; axprobe findings 2026-07-31).
   - `AXUIElementSetMessagingTimeout(2.0)` on the app element and the
     system-wide element used by the retry loop.
   - Retry loop: 24 attempts, 150 ms apart (raised from the findings' 12 after the 2026-08-02 cold-Teams acceptance run; see research.md Decision 3 amendment), `try Task.checkCancellation()`
     first in each iteration (same idiom as `TextWriter`'s modifier wait).
     Each attempt queries the app element's focused element first, then the
     system-wide focused element (findings: app element is the reliable path
     for Teams; system-wide kept as secondary).
   - An element found with a non-empty selection returns immediately. An
     element found without selection is remembered as a fallback candidate and
     retries continue (selection may appear as the tree finishes building).
     After the loop: return the candidate if any (caller then produces
     today's `cannotReadSelectedText`), else throw `noFocusedElement`.

3. **Error surface unchanged.** No new error cases; timing of failures grows by
   at most the bounded window, satisfying spec SC-003.

## Project Structure

### Documentation (this feature)

```text
specs/005-teams-ax-recovery/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0: consolidated empirical findings
├── data-model.md        # Phase 1: minimal (no persistent data)
├── quickstart.md        # Phase 1: manual acceptance / validation guide
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Support/
│   └── AXHelpers.swift        # recovery path added to getFocusedElement
├── Core/
│   └── SelectionReader.swift  # opts in: getFocusedElement(wakeDormantTree: true)
docs/
└── compatibility.md           # dormant-tree entry + re-verified acceptance
Tests/OvertypeTests/           # unchanged; suite must stay green
```

**Structure Decision**: single existing SPM target; the behavior change is
contained in `Support/AXHelpers.swift` with a one-line opt-in from
`Core/SelectionReader.swift` and documentation updates. No new files needed.

## Complexity Tracking

No constitution violations; table not required.
