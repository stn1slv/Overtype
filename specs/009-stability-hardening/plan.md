# Implementation Plan: Stability Hardening

**Branch**: `speckit/009-stability-hardening` | **Date**: 2026-08-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-stability-hardening/spec.md`, plus the
approved review fix plan (2026-08-08 deep bug review of commit `eda5ad2`), which contains
the verified file/line locations for every finding.

## Summary

Fix 7 critical (crash or data loss) and 8 high (reliability) defects: C1 shortcut
decode trap, C2 unclamped typing chunk size, C3 fragile config decoding, C4
non-atomic Keychain writes, C5 dual Settings drafts, C6 missing save rollback,
C7 dead config reload, H1 uncancellable/unbounded read phase, H2 leaked
process-global AX timeout, H3 silent chunk drop, H4 launch-only trust check,
H5 undefended OpenAI-compatible provider, H6 inert Ollama truncation guard,
H7 broken unified logging and unreachable debug mode, H8 incomplete modifier
handling. No new features; every change traces to a finding id.

## Technical Context

**Language/Version**: Swift 5.9

**Primary Dependencies**: SwiftUI, AppKit, ApplicationServices (AX), Security (Keychain), vendored KeyboardShortcuts 1.15.0 (unchanged by this feature)

**Storage**: `~/Library/Application Support/Overtype/config.json` (Codable JSON); macOS Keychain for credentials

**Testing**: XCTest via `swift test` (SPM; requires the Xcode toolchain via `DEVELOPER_DIR` if the CLT toolchain is active)

**Target Platform**: macOS 13+

**Project Type**: Desktop menu bar accessory (single SPM package, no Xcode project)

**Performance Goals**: Escape aborts the read phase in at most 5 s against an unresponsive target; read phase hard timeout 30 s (clarified 2026-08-08)

**Constraints**: No clipboard; non-destructive by default; typed errors only; no selected text, model output, or secrets at info+ logs; system-boundary changes need manual acceptance entries in `docs/compatibility.md`

**Scale/Scope**: 15 findings across 16 source files plus tests; medium/low review backlog explicitly out of scope

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Clipboard Isolation**: PASS. No change touches the clipboard; `rg NSPasteboard Sources/ Vendor/` stays part of the PR checklist.
- **II. Non-Destructive by Default**: PASS, strengthened. C2 and H3 close the two paths where the selection is destroyed and the replacement silently incomplete; the existing pre-write context re-check is untouched. H3 adds a typed partial-write error for the one unavoidable post-delete failure, which is the honest behavior Principle II plus VI require.
- **III. Evidence Over Assumption**: PASS. The C2 chunk cap (near 20 UTF-16 units) is treated as an assumption until the diagnostic run in quickstart.md verifies it; the clamp design is safe for any actual cap. H2 and H8 changes touch verified quirk workarounds, so their inline quirk comments are preserved and the affected `docs/compatibility.md` scenarios are re-run before merge. No AX return code is newly trusted.
- **IV. Configuration Over Code**: PASS. C3 makes hand-edited configuration strictly more usable; no automation requires code; the provider protocol shape is unchanged (H5 refactors inside one provider and extracts a shared pure helper).
- **V. Privacy and Secret Handling**: PASS, strengthened. H7 makes the debug switch emit the explicit privacy warning the constitution requires (closing a Known Deviation); C4 and H5 log Keychain status codes and key names only, never values; no new network endpoints.
- **VI. No Silent Failure**: PASS, strengthened. C3 load notices, H3 partial-write error, H4 permission-specific error, and the H1 hard timeout all convert silent failure modes into typed, visible outcomes. Errors remain typed values.
- **VII. Native Stack, Minimal Dependencies**: PASS. No new dependencies; all fixes are first-party Swift.
- **VIII. Verification Discipline**: PASS. Every pure-logic fix gains unit tests (C1, C2, C3, C7 decision logic, H5, H6); system-boundary changes (C4, C5, H1, H2, H3, H4, H8) get manual acceptance items recorded in `docs/compatibility.md`; no mock-based AX tests are added.

Post-design re-check (after Phase 1): no violations introduced; Complexity Tracking stays empty.

## Project Structure

### Documentation (this feature)

```text
specs/009-stability-hardening/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output (validation guide)
├── contracts/
│   ├── config-tolerance.md          # Effective config.json decode contract after C3
│   └── openai-response-handling.md  # Response-shape contract after H5
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

Touch-points, by finding. This list is the drift baseline for the cycle.

```text
Sources/Overtype/
├── Config/
│   ├── AppConfig.swift            # C1 (shortcut validity), C3 (tolerant decoding)
│   └── ConfigStore.swift          # C3 (issue collection + notice), C7 (reload() gains callers)
├── Core/
│   ├── ActionEngine.swift         # H1 (hard timeout wrapper), H4 (per-run trust check)
│   ├── HotkeyManager.swift        # C1 (skip invalid shortcuts with warning)
│   └── TextWriter.swift           # C2 (cadence clamp), H3 (typed partial-write error), H8 (Shift + flags)
├── Providers/
│   ├── AIProvider.swift           # H5 (shared reasoning-strip helper location)
│   ├── OpenAICompatibleProvider.swift  # H5 (parse seams, refusal/empty mapping, keychain logging)
│   └── OllamaProvider.swift       # H5 (delegate to shared helper), H6 (effective-window clamp)
├── Security/
│   └── KeychainStore.swift        # C4 (update-or-add, status surfacing, LocalizedError)
├── Support/
│   ├── AXHelpers.swift            # H1 (cancellation points, bounded messaging), H2 (timeout restore)
│   ├── Logger.swift               # H7 (%{public}@, UserDefaults-backed debug switch + warning)
│   └── PermissionManager.swift    # H4 (helper reuse; no structural change expected)
├── UI/
│   ├── Settings/
│   │   ├── SettingsWindow.swift   # C5 (shared view model)
│   │   ├── SettingsViewModel.swift # C6 (rollback), C7 (real reload + snapshot)
│   │   ├── GeneralTab.swift       # C2 (formatter bounds)
│   │   └── ActionsTab.swift       # C1 (handle invalid stored shortcut)
│   └── (FeedbackPresenter.swift unchanged)
└── OvertypeApp.swift              # C5 (single shared draft), H4 (poll start on trust loss), C3 (notice surfacing)

Tests/OvertypeTests/
├── AppConfigTests.swift           # C1, C3 additions (wrong-type + lossy decode)
├── TypingProfileTests.swift       # C2 additions (clamps)
├── OpenAICompatibleProviderTests.swift  # NEW (H5)
├── OllamaProviderTests.swift      # H5 (helper still covered), H6 additions
├── ReasoningStripTests or reuse   # H5 (shared helper coverage stays green)
└── SettingsReloadTests.swift      # NEW (C7 decision logic)

docs/compatibility.md              # Manual acceptance results (C2 cap, H1, H2, H4, H8, C4, C5)
```

**Structure Decision**: single SPM package, existing layout; no new targets or directories beyond test files.

## Design by finding

Authoritative fix directions; file and line references are from the review of `eda5ad2`.

### C1 - Shortcut values must never trap
`ActionShortcut.keyboardShortcut` (AppConfig.swift:148-153) becomes optional: it returns
nil when `keyCode < 0` or `modifiers < 0` instead of trapping in `UInt(_:)`. The valid
path converts with `UInt(bitPattern:)` only after the guard, so no conversion can trap.
`HotkeyManager.registerHotkeys` skips a nil shortcut with a `.warning` log naming the
action title. `ActionsTab.prepareEditForm` seeds the recorder only from a non-nil value.
Tests: negative modifiers, negative keyCode, valid values, and registration filtering.

### C2 - Typing cadence clamped at one choke point
`TextWriter.typingProfile` clamps the resolved chunk size to `1...20` and the delay to
`>= 0` after override resolution (both global and per-app values pass through it). The
upper bound 20 is the assumed synthetic-event cap pending the quickstart diagnostic; the
clamp is correct for any real cap at or above 20. `chunkRanges`' `chunkSize > 0` guard
switches from "one giant range" to chunking at the default size (defense in depth; the
clamp upstream already prevents it). `writeViaCGEvent` logs a `.warning` when the profile
differs from the configured raw values (mirrors the retry-delay clamp pattern, keeping
`typingProfile` pure). `GeneralTab`'s three cadence `NumberFormatter`s get `minimum = 0`
(0 stays the "unset" sentinel). Tests: 0, negative, huge, and boundary values, global and
override paths.

### C3 - Lossy, type-tolerant configuration decoding
A reference collector (`ConfigDecodingIssues`, a final class holding `[String]`) is passed
through `JSONDecoder.userInfo` by `ConfigStore`. Decoding rules:
- Scalar fields that have defaults fall back on type mismatch as well as absence
  (`(try? decodeIfPresent) ?? default`), recording an issue naming the key.
- `baseURL` decodes as `String?` and converts via `URL(string:)`; failure records an
  issue and yields nil (run-time typed error later, as today).
- `providers` and `actions` decode per element via a `FailableDecodable<T>` wrapper: an
  element that fails (missing required field, unknown `kind`, wrong-typed required field)
  is dropped alone, recording an issue with the element's id or index.
- `ActionShortcut.displayString` tolerates absence (defaults to "") so a cosmetic field
  cannot drop an action.
- Required-per-element fields stay required: provider `id`/`kind`/`defaultModel`; action
  `id`/`title`/`providerID`/`systemPrompt`/`userPromptTemplate`.
`ConfigStore` turns a non-empty issue list into a `loadWarningMessage` (new, alongside
`loadFailureMessage`) surfaced by the existing AppDelegate alert path, and logs each
issue at `.warning`. Issue strings name keys and ids only, never values (Principle V:
config contains user prompts). Contract: `contracts/config-tolerance.md`.
Tests: one wrong-type test per field family, per-element drop, unknown kind, invalid
URL, notice accumulation.

### C4 - Atomic Keychain replace with surfaced status
`KeychainStore.store` becomes: search query (`kSecClass` + `kSecAttrAccount`, no
`kSecValueData`); if `SecItemCopyMatching` finds the item, `SecItemUpdate` with the new
data; else `SecItemAdd`; an `errSecItemNotFound` race on update falls through to add.
The old credential is never deleted ahead of a successful write. `KeychainError` gains
`LocalizedError` conformance; `unhandledError` renders the numeric `OSStatus` plus
`SecCopyErrorMessageString` text. Item identity deliberately stays account-only (no
`kSecAttrService`), so existing user credentials keep working; a comment records the
trade-off. Tests: error-message rendering (pure); store/update/delete round-trip goes to
manual acceptance (system boundary).

### C5 - One shared Settings draft
`SettingsViewModel` gains a `static let shared` instance. `SettingsWindow` switches from
`@StateObject` creating its own instance to `@ObservedObject` defaulting to `.shared`
(the object outlives any window, so `ObservedObject` is the correct wrapper). Both entry
points (the SwiftUI `Settings` scene and the AppDelegate window) then edit the same
draft and cannot revert each other. Manual acceptance: dual-window edit/save scenario.

### C6 - Rollback in the two unprotected mutators
`saveAction` create path: on `saveSettings()` throw, `actions.removeLast()` before
rethrowing. Edit path: restore the original element. `toggleActionEnabled`: un-toggle on
throw. Mirrors the existing pattern in `saveProvider`/`deleteProvider`/`deleteAction`.

### C7 - reloadFromDisk that actually reloads
`SettingsViewModel` keeps a `lastLoaded` snapshot (config plus overrides list), set in
`init` and after every successful `saveSettings`. `reloadFromDisk()` first calls
`ConfigStore.shared.reload()` (throw: log `.warning`, keep current state), then compares
the draft against `lastLoaded` (not against the store): unsaved edits present, keep the
draft; draft clean, adopt the freshly loaded config, rebuild the overrides list, update
`lastLoaded`, and post `.overtypeConfigDidChange` so hotkeys and providers pick up
external edits. The unsaved-edit decision is extracted as a pure function and unit
tested. Manual acceptance: hand-edit while running, refocus Settings.

### H1 - Cancellable, bounded read phase
`AXHelpers.getFocusedElement` adds `try Task.checkCancellation()` before each strategy
and at every DFS node visit (the DFS becomes throwing). AX messaging is bounded for the
whole read by a scoped helper (see H2). `ActionEngine.run` wraps `readSelection()` in a
30 s hard-timeout race (task group: the blocking read on one child, a cancellable 30 s
sleep on the other; the loser is cancelled; timeout throws `ProviderError.timeout`).
After a timeout, the abandoned read thread is still bounded by the 2 s per-call AX
messaging cap and exits on its next cancellation check. Manual acceptance: Escape and
timeout behavior against an unresponsive target; Teams recovery unchanged.

### H2 - Scoped, restored AX messaging timeout
A helper `withBoundedAXMessaging(_:)` sets the system-wide messaging timeout (2 s) on
entry and restores it to 0 (system default) in a `defer`. The read phase (strategies,
DFS, and dormant-tree recovery) runs inside it; `retryFocusLookup` drops its own
never-restored system-wide call. The pre-write re-check deliberately stays outside (its
single-shot call must fail fast; the quirk comment stays). `docs/compatibility.md` gets
a re-run of the Teams dormant-tree scenario plus a new "behavior after recovery"
acceptance item.

### H3 - Typed partial-write error
The `continue` on failed `CGEvent` creation (TextWriter.swift:159-163) becomes `throw
AXError.writeIncomplete` (new case). Its `errorDescription` states the replacement may
be incomplete and the original text was already replaced in part. The engine's existing
catch arms surface it like any other typed error. Log at `.error` with chunk index and
count only.

### H4 - Trust evaluated per run, monitors self-heal
`ActionEngine.run` starts with `AXIsProcessTrusted()`; when false it shows a new typed
error (`AXError.accessibilityPermissionRevoked`, message naming System Settings) and
posts a new notification (`.overtypeAccessibilityTrustLost`). `AppDelegate` observes it
and starts the existing 3 s poll timer (if not already running), which reinstalls the
Escape monitors on re-grant, exactly as the launch path does. No change to
`PermissionManager`'s prompt logic.

### H5 - OpenAI-compatible provider hardening
The reasoning-block stripper moves from `OllamaProvider` to a shared internal helper
(`ResponseReasoningStripper` in Providers/, pure; `OllamaProvider` delegates so its 745
lines of tests stay green). `OpenAICompatibleProvider` gains seams matching the other
providers: `endpointURL(base:)` and `parseResponseText(from:)` (static, pure). Parsing:
`message.refusal` present or `finish_reason == "content_filter"` maps to
`.responseBlocked(reason:)` using a short category, never the raw refusal text in logs;
missing/null content or empty-after-sanitizing maps to `.emptyResponse`; the happy path
strips a leading reasoning block before returning. The Keychain catch distinguishes
`itemNotFound` (`.apiKeyMissing`) from other statuses (still `.apiKeyMissing` for the
HUD, plus a `.warning` log with the key name and status label, mirroring
`OllamaProvider.authorizationHeader`). New `OpenAICompatibleProviderTests` covers URL
building, refusal, content-filter, null/empty content, reasoning strip, and error
extraction. Contract: `contracts/openai-response-handling.md`.

### H6 - Effective-window truncation threshold
`OllamaProvider.grantedContextWindow` returns `min(Self.contextWindowTokens, reported)`
so `truncationThreshold` and `promptBudget` both see the effective window. The comment
at lines 146-154 is corrected to state both clamp directions. Tests: trained windows
40960 and 131072 must yield a threshold of 8192.

### H7 - Readable logs, reachable debug mode
`Logger.log` switches to `os_log("%{public}@", ...)`. `isDebugEnabled` initializes from
`UserDefaults.standard.bool(forKey: "OvertypeDebugLogging")` in `init`, and when true
the initializer logs one `.warning` stating that selected text and model output will
appear in logs (the explicit user warning Principle V requires; closes the Known
Deviation). No new UI. Verified live via `/usr/bin/log stream --predicate 'subsystem ==
"com.github.stn1slv.Overtype"'`.

### H8 - Shift in the wait; cleared flags on typed chunks
Add `.maskShift` to the modifier-release condition (TextWriter.swift:100-102) and set
`flags = []` on the chunk `eventDown`/`eventUp` pair, matching `postKey`. The file's
quirk comment is updated to match the code. Manual acceptance re-runs the typing
scenarios for the verified apps (Outlook, Teams) before merge.

## Complexity Tracking

No constitution violations to justify; table intentionally empty.
