# Research: Dormant Accessibility Trees (Teams) and the Recovery Parameters

**Date**: 2026-08-02
**Status**: Complete. All technical unknowns resolved by two recorded empirical
sources; no open NEEDS CLARIFICATION items.

## Sources

1. **axprobe findings report, 2026-07-31** ("Platform Findings: Reading and
   Writing Selected Text on macOS", axprobe v1-v3). Key results reused here.
2. **Live diagnostic, 2026-08-02** (this repository's Teams regression
   investigation; unified log of subsystem `com.github.stn1slv.Overtype` plus
   three throwaway probes run against the live Teams process, pid 965).

## Decision 1: Why Teams stopped working (root cause)

- **Decision**: Treat the failure as a dormant, lazily-built accessibility
  tree in the target app, not as an Overtype code regression.
- **Rationale**: Timeline evidence from the 2026-08-02 diagnostic:
  - Teams process restarted 11:29. Every Overtype run against Teams that
    evening failed with `noFocusedElement` in ~12 ms (instant `noValue` from
    every AX query; log entries 20:12-21:09).
  - At 21:10 a probe set `AXEnhancedUserInterface = true` on the Teams app
    element. With **zero changes to Overtype**, runs at 21:13:59 and 21:15:09
    read 317- and 274-character selections from `com.microsoft.teams2` and
    completed successfully.
  - The same failure signature existed on 2026-08-01 under the previous build,
    so the day's refactors (PRs #5-#9) were ruled out.
  - The axprobe findings independently show the lazy-tree behavior: VS Code
    returned `noValue`, then a fully populated tree 13 seconds later with no
    other change.
- **Alternatives considered**: (a) Accessibility permission invalidated by the
  ad-hoc re-sign - ruled out because Outlook worked and no permission warnings
  were logged after re-grant; (b) regression in PR #5's rewritten
  `getFocusedElement` - ruled out by the Aug 1 log evidence and by diff review
  (the selection-gating change cannot produce `noFocusedElement` when the app
  element itself returns `noValue`); (c) Teams update - ruled out (binary
  unchanged since Jul 22).

## Decision 2: Wake mechanism - set both flags, ignore result codes

- **Decision**: Set `AXEnhancedUserInterface = true` and
  `AXManualAccessibility = true` on the target app element and ignore the
  returned `AXError` values.
- **Rationale**:
  - Teams: the `AXEnhancedUserInterface` set call **returns
    `.notImplemented` (-25208) yet takes effect** - read-back flips 0 to 1 and
    the tree activates (2026-08-02, direct observation). This is the mirror
    image of the already-documented Teams quirk where a set call returns
    success and does nothing: in both directions, AX return codes are not
    evidence (constitution Principle III).
  - `AXManualAccessibility` is rejected by Teams (`attributeUnsupported`) but
    accepted by Electron apps (VS Code, Claude desktop - axprobe findings),
    so setting both covers both families for free.
  - The axprobe findings' own v2/v3 successes set both switches before every
    lookup; the report attributed success to the retry loop and called the
    switches "contributed nothing measurable", which the 2026-08-02 experiment
    corrects: for Teams the `AXEnhancedUserInterface` flag is the decisive
    warm-up, and it persists for the lifetime of the Teams process.
- **Alternatives considered**: relying on query pressure alone to wake
  Chromium (rejected: axprobe v1 issued repeated queries and failed 5/5);
  asking the user to run VoiceOver once (rejected: manual, absurd UX).

## Decision 3: Retry configuration - app-element-first, 24 x 150 ms, 2 s messaging timeout

- **Decision**: After setting the flags, retry the focused-element lookup up
  to 24 times at 150 ms intervals, querying
  `AXUIElementCreateApplication(pid)` first and the system-wide element
  second, with `AXUIElementSetMessagingTimeout(2.0)` applied to both.
- **Rationale**: This is the exact configuration validated by axprobe v2/v3
  (binding conclusion #3 of the findings report): Teams 11/11 successful reads
  (attempt 1 in 10 cases, attempt 2 in 1), Outlook 4/5 with 1 correct
  empty-selection report. The system-wide path alone failed 5/5 on Teams, so
  app-element-first ordering matters. The messaging timeout bounds each query
  against a hung AX server so the whole recovery stays within the run's hard
  timeout.
- **Amendment (2026-08-02, acceptance run)**: the findings' 12 attempts were
  measured against a partially warmed Teams. The first acceptance run against
  a truly cold Teams (pid 46804, 21:40) showed the focused element appears
  quickly after the wake but its `kAXSelectedText` populates only ~2.7 s in,
  so 12 x 150 ms (1.8 s) expired just short and the first press ended in
  `cannotReadSelectedText` (the second press then succeeded instantly). The
  attempt count was raised to 24 (~3.5 s) to cover the observed cold latency
  with margin. VS Code's recorded 13 s outlier remains out of reach by
  design; a second press covers it.
- **Alternatives considered**: rerunning the full 5-strategy chain each
  attempt (rejected: the DFS crawl is the expensive part and the findings
  show the app element is what recovers); unbounded/adaptive windows
  (rejected: the bounded window keeps failures fast and cancellable).

## Decision 4: Recovery only on the read path, not the pre-write re-check

- **Decision**: Only `SelectionReader.readSelection()` opts into recovery. The
  `ActionEngine` pre-write context re-check keeps single-shot behavior.
- **Rationale**: by write time the tree is warm (the run just read from it),
  and Principle II wants a changed context to abort fast; adding up to 1.8 s
  of retries to the abort path would enlarge the window in which the user's
  focus change races the write.
- **Alternatives considered**: recover everywhere (rejected for the reason
  above); a separate public wake-up API called by `ActionEngine` (rejected:
  wider surface, same effect).

## Known side effects and their mitigation

- `AXEnhancedUserInterface` is the flag VoiceOver sets; in some Electron apps
  it has historically triggered window-resize/zoom glitches. Mitigation: the
  flags are set **only after all normal strategies have failed**, i.e., only
  for apps that are currently unusable with Overtype anyway, and at most once
  per run.
- The flags change state in the target process that persists until that app
  restarts. This is precisely the intended effect (it is what assistive
  clients do); no cleanup is attempted.
