# Quickstart & Manual Acceptance: 005-teams-ax-recovery

This feature changes system-boundary behavior (Accessibility API), so per the
constitution (Principle VIII) it is validated by this manual procedure against
real applications, not by mocked unit tests. Record results in
`docs/compatibility.md` before release.

## Prerequisites

- Build the bundle: `./scripts/build-app.sh` (produces `Overtype.app`).
- Re-grant Accessibility permission after the rebuild (ad-hoc signature
  changes invalidate the previous grant): System Settings > Privacy &
  Security > Accessibility.
- A configured action with a working provider key (e.g. "Fix grammar").
- Watch logs while testing:
  `/usr/bin/log stream --predicate 'subsystem == "com.github.stn1slv.Overtype"' --info`
  (note: use `/usr/bin/log`; in zsh the bare `log` is a shell builtin).

## A. Baseline (unit tests)

```bash
swift test
```

Expected: all tests pass before and after the change.

## B. Cold-Teams recovery (the fix itself) - SC-001, SC-005

1. Quit Microsoft Teams completely (Cmd+Q, verify with `pgrep MSTeams`), then
   relaunch it. Do NOT run VoiceOver or any other assistive tool.
2. In the Teams compose box, type a sentence with an obvious grammar error and
   select it.
3. Press the action hotkey.

Expected: HUD shows Reading → Thinking → Writing; the selection is replaced
correctly. The first run may take up to ~2-3 s longer than a warm run (the
recovery window). The log shows the recovery attempt count.

4. Repeat once more from a fresh Teams restart (SC-005 requires twice in a
   row).

## C. Warm fast path unchanged - SC-002

1. Immediately after B, run the action again in Teams. Expected: normal speed,
   no recovery messages in the log.
2. Run the action in New Outlook and in a native app (e.g. Notes). Expected:
   unchanged behavior and latency; no wake flags set (no recovery log lines).

## D. Failure timing and cancellation - SC-003, SC-004

1. Focus a Teams window with **nothing selected** and press the hotkey.
   Expected: the same specific error as before the change, arriving within
   about two seconds (the bounded retry window), never an indefinite wait.
2. Restart Teams again (cold tree), select text, press the hotkey and
   immediately press Escape during the Reading phase. Expected: run cancels
   promptly (< 1 s), HUD disappears, the document is untouched.

## E. Regression sweep

Re-run the action once in each previously verified app (Outlook, a native
Cocoa app, VS Code if available) and confirm behavior matches the entries in
`docs/compatibility.md`.

## Recording

Update `docs/compatibility.md`:

- Add the dormant-tree note for Teams (cold restart behavior, wake-flag quirk
  with its error-code caveat, recovery window).
- Record date + pass/fail for scenarios B-E.
