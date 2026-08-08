# Quickstart Validation: Stability Hardening

How to prove the feature works end to end. References: [spec.md](spec.md) success
criteria SC-001..SC-007, [contracts/](contracts/), [data-model.md](data-model.md).

## Prerequisites

- Xcode toolchain active for tests: if `swift test` fails with "no such module
  'XCTest'", run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- A built bundle for manual items: `./scripts/build-app.sh`, then re-grant
  Accessibility in System Settings > Privacy & Security (ad-hoc signature changes on
  every rebuild).
- Config path: `~/Library/Application Support/Overtype/config.json`. Back it up before
  fixture testing; restore afterwards.

## 1. Unit suite (SC-005)

```bash
swift test
```

Expected: all previously passing tests (229 at baseline) still pass, plus the new
suites: shortcut validation (C1), cadence clamps (C2), lossy decoding (C3),
Keychain error rendering (C4), reload decision (C7), OpenAI-compatible parsing (H5),
Ollama window clamp (H6).

## 2. Malformed-config launch matrix (SC-001)

For each fixture, replace config.json, launch the built app, and verify: it launches,
the menu bar item appears, a single warning notice names what was ignored, and all
valid providers/actions are present in Settings.

| Fixture | Expect |
|---|---|
| `"modifiers": -1` on an enabled action's shortcut | Launches; that hotkey inactive; warning names the action (C1) |
| `"typingChunkSize": 0` | Launches; a run types the full replacement; clamp warning in log (C2) |
| `"showHUD": "true"` (string) | Launches; HUD default on; field named in notice (C3) |
| `"baseURL": "not a url"` | Launches; provider present; run fails with the typed URL error (C3) |
| `"kind": "openrouter"` | Launches; that provider dropped by name; actions intact (C3) |

## 3. Write-integrity checks (SC-003)

- With chunk size clamped (fixture above), run an action over a 4000+ character
  selection in TextEdit: the full replacement must appear.
- Diagnostic (Principle III, records the real event cap): type a fixture string of
  30+ UTF-16 units through a single synthetic event in a scratch build or debugger and
  record the observed cap in `docs/compatibility.md`; confirm the production clamp (20)
  is at or below it. Include one surrogate-pair boundary case (emoji at position 20).

## 4. Cancellation and timeout (SC-002)

- Freeze a target app (`kill -STOP <pid>` of a test editor), select text first, then
  trigger an action; press Escape during "Reading...": run aborts within 5 s.
- Same setup, no Escape: run ends with the typed timeout error at 30 s.
- `kill -CONT` the target afterwards.
- Teams dormant-tree scenario from `docs/compatibility.md`: unchanged result after the
  H1/H2 changes, and a post-recovery run against a different app behaves like a fresh
  launch (H2).

## 5. Settings integrity (SC-004, C5, C6, C7)

- Dual window: open Settings from the menu bar, press Cmd+comma while it is key; edit
  and save in each window; verify no saved change from the other window is lost.
- Failed-save retry: create an invalid duplicate per-app override row on General, then
  save a new action on Actions (fails); fix the row; save again: exactly one action.
- External edit: with the app running, hand-edit config.json (add an action); refocus
  Settings with no unsaved edits: the new action appears; saving does not revert it.
- Credential: with a stored key, enter a new key and force a save failure (e.g. locked
  keychain via `security lock-keychain login.keychain-db`), unlock, verify the previous
  key still works and the error named the status (C4).

## 6. Permission lifecycle (SC-007)

- Launch trusted, then remove Overtype from Accessibility while it runs; trigger an
  action: the error names the missing permission (not "cannot find text element").
- Re-grant without relaunching: within a few seconds Escape cancellation works again.

## 7. Provider behavior (H5, H6)

- Point an `openai` provider at a local server that emits `<think>` blocks (e.g. an
  Ollama `/v1` endpoint with a reasoning model): the typed result contains no reasoning.
- Unit fixtures cover refusal / content-filter / null-content / empty (contract:
  [openai-response-handling.md](contracts/openai-response-handling.md)).
- H6 is unit-verified (thresholds for 40960 and 131072 trained windows equal 8192).

## 8. Diagnostics (H7)

```bash
defaults write com.github.stn1slv.Overtype OvertypeDebugLogging -bool true
/usr/bin/log stream --predicate 'subsystem == "com.github.stn1slv.Overtype"'
```

Expected: readable message text (no garbled `%s` output); one privacy warning logged at
startup when the flag is on; debug lines appear only with the flag on. Note: use
`/usr/bin/log`, the bare `log` is shadowed by a zsh builtin.

## 9. Record results

Record every manual item's outcome in `docs/compatibility.md` (per app where
applicable). A release must not ship with any item regressed (constitution VIII).
