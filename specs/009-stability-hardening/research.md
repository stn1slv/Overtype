# Phase 0 Research: Stability Hardening

No NEEDS CLARIFICATION markers remained in the Technical Context (the 2026-08-08 review
plus the spec clarification session resolved them). This file records the design
decisions and the alternatives considered, so the choices are not re-litigated during
implementation.

## D1. Invalid shortcut handling (C1)

- **Decision**: make `ActionShortcut.keyboardShortcut` optional; nil for negative
  `keyCode`/`modifiers`; convert with `UInt(bitPattern:)` after the guard; callers skip
  nil with a warning.
- **Rationale**: validation at the single computed property covers both call sites
  (hotkey registration and the Actions editor); `UInt(bitPattern:)` alone would register
  a nonsense hotkey instead of failing visibly.
- **Alternatives considered**: rejecting the whole action during decode (drops a valid
  action over a repairable field); clamping to 0 (registers a wrong shortcut silently).

## D2. Chunk-size clamp bound (C2)

- **Decision**: clamp resolved chunk size to `1...20` in `typingProfile`; treat 20 as
  the assumed synthetic-event cap until the diagnostic run in quickstart.md verifies the
  real cap; log a warning when the clamp engages.
- **Rationale**: the shipped default is 20 and the per-app override in use is 1, so the
  clamp changes no working configuration; a cap-safe bound is correct regardless of the
  empirical result (Principle III).
- **Alternatives considered**: no upper bound (leaves the silent-truncation path open
  for large hand-edited values); clamping inside `chunkRanges` (hides the correction
  from the log and leaves `typingProfile` returning impossible values).

## D3. Lossy decoding mechanism (C3)

- **Decision**: a `FailableDecodable<T>` element wrapper for arrays plus
  `(try? decodeIfPresent) ?? default` for defaulted scalars, with an issue collector
  passed via `JSONDecoder.userInfo` and surfaced by `ConfigStore` as a warning notice.
- **Rationale**: standard Codable patterns, unit-testable without I/O, and the collector
  keeps decoders side-effect free while still satisfying "no silent failure".
- **Alternatives considered**: schema pre-validation before decode (a second parser to
  maintain); making every field optional in the model (pushes nil-handling into every
  consumer); logging directly from decoders (side effects in `init(from:)`, untestable
  ordering).

## D4. Keychain replace flow (C4)

- **Decision**: search (attributes only), then `SecItemUpdate`, else `SecItemAdd`;
  never delete ahead of a successful write; add `LocalizedError` with the `OSStatus`
  and `SecCopyErrorMessageString` text; keep account-only item identity.
- **Rationale**: update-in-place is the atomic primitive the API offers; account-only
  identity keeps every existing stored credential working without migration.
- **Alternatives considered**: adding `kSecAttrService` (orphans existing credentials
  unless migrated; migration is out of scope for a hardening feature); delete-then-add
  with rollback (there is no way to restore a deleted keychain item).

## D5. Single settings draft (C5)

- **Decision**: `SettingsViewModel.shared`, consumed via `@ObservedObject`.
- **Rationale**: the view model must outlive any window to be shared, which is exactly
  the `ObservedObject` contract; the smallest change that removes the second draft.
- **Alternatives considered**: removing the SwiftUI `Settings` scene (an `App` needs a
  scene, and an empty scene still opens a blank window on Cmd+comma); window-to-window
  merge logic (complex, still racy).

## D6. External-edit reload (C7)

- **Decision**: `reloadFromDisk()` calls `ConfigStore.reload()` first, then compares the
  draft against a `lastLoaded` snapshot; clean drafts adopt the new config and post the
  config-changed notification.
- **Rationale**: comparing against the snapshot (not the store) is the only way to
  distinguish "user has unsaved edits" from "someone else changed the config", which is
  the confusion that made the current guard a permanent no-op.
- **Alternatives considered**: file-watcher on config.json (new machinery, same decision
  logic still needed); mtime checks (races with the app's own saves).

## D7. Read-phase bounding (H1, H2)

- **Decision**: cancellation checks before each strategy and per DFS node; a scoped
  `withBoundedAXMessaging` helper that sets the system-wide 2 s messaging timeout and
  restores it to 0 in `defer`; a 30 s hard-timeout race in `ActionEngine` around
  `readSelection()` (clarified value).
- **Rationale**: per-call bounding plus cancellation gives Escape a worst case of one
  bounded AX call (SC-002's 5 s holds with margin); the scoped helper simultaneously
  fixes H2's permanent process-global leak; the race is the only way to bound a
  synchronous, uninterruptible AX call stack from the outside.
- **Alternatives considered**: per-element timeouts only (leaves strategy-1's
  system-wide element unbounded); moving the read to async AX observers (a rewrite of
  verified quirk workarounds, forbidden without new diagnostics by Principle III).

## D8. Partial-write failure (H3)

- **Decision**: throw a new typed `AXError.writeIncomplete` and stop typing.
- **Rationale**: after the destructive delete there is no safe retry; the choice is
  silent corruption plus a success report versus a truthful typed error. Principle VI
  decides it.
- **Alternatives considered**: keep typing remaining chunks (the missing interior chunk
  corrupts the text anyway); retrying event creation (the failure is a system-resource
  condition a retry will not fix mid-burst).

## D9. Trust re-check placement (H4)

- **Decision**: `AXIsProcessTrusted()` at the top of `ActionEngine.run`; new typed
  error; notification to AppDelegate to start the existing poll/reinstall timer.
- **Rationale**: the run entry point is the one place every trigger passes through; the
  poll and monitor-reinstall machinery already exists and is verified.
- **Alternatives considered**: a permanent poll while trusted (wasteful; the existing
  QUIRK comment only justifies polling in the untrusted state); observing the TCC
  database (private API).

## D10. Reasoning-strip sharing (H5)

- **Decision**: extract `OllamaProvider.stripLeadingReasoningBlock` into a shared pure
  helper used by both providers; keep Ollama's tests green by delegation.
- **Rationale**: the logic is already written, tested, and documented; duplicating it
  would drift.
- **Alternatives considered**: moving it into `ResponseSanitizer` (runs after provider
  mapping and would apply to Gemini/Anthropic too, changing verified behavior of
  providers that already filter reasoning structurally).

## D11. Debug switch form (H7)

- **Decision**: `UserDefaults` key `OvertypeDebugLogging`, read once at logger init,
  with a `.warning` privacy notice when enabled; no UI.
- **Rationale**: "no new features" rules out a Settings surface; a defaults key is the
  standard macOS mechanism for a documented troubleshooting flag and is scriptable
  (`defaults write`).
- **Alternatives considered**: environment variable (not persistent across launches from
  Finder); config.json field (config is user-synced state, and the flag must survive a
  config reset).

## Empirical items deferred to the acceptance run (Principle III)

- The real `keyboardSetUnicodeString` size cap, including the 21-unit surrogate
  extension case (C2): diagnostic procedure in quickstart.md; result recorded in
  `docs/compatibility.md`.
- Whether a held physical Shift can leak into `.privateState` chunk events before the
  H8 fix, and that typing behavior in Outlook/Teams is unchanged after it.
- Teams dormant-tree recovery timing after the H2 scoped-timeout change.
