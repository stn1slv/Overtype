# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Overtype is a native macOS menu bar utility (Swift 5.9, macOS 13+, SwiftUI) that
replaces selected text in *any* application with an AI transformation (e.g.
grammar fix). The user selects text, presses a global hotkey, and the selection
is overwritten inline. It runs as a menu bar accessory with no Dock icon.

## Commands

Swift Package Manager is the build system (no Xcode project). A `Makefile` at the
repo root wraps the common tasks (`make build|test|lint|format|run|clean|setup|upgrade-deps`);
each target delegates to the SPM/`swift` commands below. Run `make help` to list them.

- Build (debug): `swift build`
- Build (release): `swift build -c release`
- Build the distributable `.app` bundle (release build + Info.plist + ad-hoc codesign): `./scripts/build-app.sh` — produces `Overtype.app` in the repo root. The script also stamps the version into the bundle's `Info.plist`, editing only the bundle copy and never `Sources/Overtype/Resources/Info.plist`. The two keys resolve independently: `CFBundleShortVersionString` is stamped only when `$OVERTYPE_VERSION` is set or `HEAD` is tagged (otherwise the checked-in fallback stands), while `CFBundleVersion` is stamped from `git rev-list --count HEAD` only when the full history is available. In a shallow clone or with no git metadata the script warns and leaves the fallback in place, so the build reports `0` rather than a truncated count; the release workflow's `fetch-depth: 0` exists to keep the real count available. A local build in a full clone therefore reads as the fallback version paired with a real commit count. The stamping must stay **before** the `codesign` call, which seals `Info.plist`. [Source: specs/006-settings-version-display]
- Run all tests: `swift test`
- Run one test class: `swift test --filter ConfigStoreTests`
- Run one test method: `swift test --filter ResponseSanitizerTests/testSomeName`
- Launch the app after building: open the generated `Overtype.app` (running the raw executable is not a faithful launch; the app needs its bundle/Info.plist to behave as a menu bar accessory).

Release is tag-driven: pushing a `v*` tag runs `.github/workflows/release.yml`,
which builds the bundle, uploads it to a GitHub release, and publishes the
Homebrew cask via `scripts/publish-cask.sh`.

### Accessibility permission caveat

The Accessibility permission macOS grants is bound to the binary's code
signature. After any rebuild that changes the signature (including local ad-hoc
builds via `build-app.sh`), the permission must be re-granted in System Settings
> Privacy & Security > Accessibility.

## Architecture

Runtime entry point is `Sources/Overtype/OvertypeApp.swift`. `AppDelegate` runs
the Accessibility permission check (`Support/PermissionManager.swift`, which uses
the native macOS prompt), creates the status-bar item, loads `ConfigStore`, has
`HotkeyManager` register a global shortcut per configured action (via the
third-party `KeyboardShortcuts` package), and installs Escape-key monitors that
cancel any in-flight run.

`KeyboardShortcuts` 1.15.0 is **vendored** under `Vendor/KeyboardShortcuts` and
consumed with `.package(path:)`, not fetched from GitHub. Upstream's
SwiftPM-generated `Bundle.module` calls `fatalError` and probes only two paths,
both unreachable from a signable `.app` (the bundle root, where macOS forbids
anything beside `Contents`, and the build machine's absolute `.build` path), so
`Settings > Actions > Add/Edit` crashed in every release. The vendored copy
carries one patch, in `Utilities.swift`, replacing that accessor with a lookup
that reads `Contents/Resources` and degrades to the untranslated key instead of
trapping. `Vendor/KeyboardShortcuts/VENDORING.md` records the upstream revision
and the exact patch; re-apply it on any upgrade and do not restore a remote pin.

The core pipeline lives in `Core/ActionEngine.swift` (`run(action:)`). One run
is a strict sequence, each stage gated on the previous succeeding:

1. `SelectionReader` reads the selected text via the Accessibility API, capturing the source `pid` and focused `AXUIElement`. The whole read runs inside `AXHelpers.withBoundedAXMessaging`, which sets a 2 s AX messaging timeout via the system-wide element (process-scoped by API contract) and restores the default in a `defer`; `getFocusedElement()` checks `Task.checkCancellation()` between strategies and at every node of its depth-first crawl, so Escape stays responsive against a frozen target. `ActionEngine.run` additionally starts by checking `AXIsProcessTrusted()` (a mid-session permission revoke gets a specific error and triggers the monitor-healing poll via `.overtypeAccessibilityTrustLost`), and races the read against `readPhaseTimeoutSeconds` (30 s), which throws the typed `AXError.readTimedOut`. [Source: specs/009-stability-hardening] `getFocusedElement()` tries five strategies, ending in the depth-first accessibility-tree crawl for Electron, New Outlook, and React Native apps that do not propagate `kAXFocusedUIElementAttribute` (an inline QUIRK WORKAROUND comment marks it). If all five fail *and* the caller passed `wakeDormantTree: true` (only `SelectionReader` does), a sixth escalation runs: `wakeDormantAccessibilityTree` sets `AXEnhancedUserInterface` and `AXManualAccessibility` on the app element, discarding both return codes, then `retryFocusLookup` retries app-element-first for 24 attempts at 150 ms, checking `Task.checkCancellation()` each pass. `ActionEngine`'s pre-write re-check (step 4) deliberately keeps the single-shot, unbounded call, so a genuine context change still aborts fast. [Source: specs/005-teams-ax-recovery]
2. The matching provider (from `ProviderRegistry`) performs the AI call. `Providers/OpenAICompatibleProvider.swift` uses `URLSession` async/await; providers conform to the `AIProvider` protocol. `ActionEngine.transformWithRetry` wraps this in exactly one automatic retry, gated on `ProviderError.isRetryable`: HTTP 408/429 and 5xx except 501, timeouts, the transient `URLError` codes in `ProviderError.retryableURLErrorCodes`, and any `.networkError` whose payload is *not* a `URLError` (unclassifiable, so it gets the one retry). Configuration errors, other 4xx codes, safety blocks, empty/invalid responses, and cancellation are never retried, since a second identical request fails the same way and only delays the error. Note that `mapTransportError` funnels every non-timeout, *non-cancelled* `URLError` into `.networkError`, including deterministic ones (`.cannotFindHost` from a typo'd `baseURL`, `.secureConnectionFailed` from a TLS misconfiguration), so `isRetryable` matches on the code rather than the case; `.cannotFindHost` is excluded deliberately and the tradeoff is written out at the declaration. The retry shows `Retrying...` in the HUD (when `showHUD` is on; like the other progress states it is a no-op otherwise) and pauses for the provider's `retryDelaySeconds` first, clamped to `0...ActionEngine.maxRetryDelaySeconds` (60s) with a warning log when the clamp engages. The pause uses cancellable `Task.sleep`, so Escape still aborts. Retrying is safe under Principle II because the write happens later, after the context re-check, so a failed call has changed nothing. Never log the error itself at `info`+: use `ProviderError.logLabel`, since `errorDescription` embeds the server message, which can echo fragments of the submitted text.
3. `Core/ResponseSanitizer.swift` cleans the model output (pure logic, unit-tested).
4. **Context re-check before writing**: the engine verifies the frontmost `pid` still matches and the focused element is still `CFEqual` to the one read. If either changed, the write is aborted and nothing is modified.
5. `Core/TextWriter.swift` writes the replacement using synthetic keyboard events / the Accessibility API, honoring the action's `writeStrategy` and global typing settings. The resolved chunk size is normalized in `typingProfile` (non-positive behaves like the Settings sentinel "unset"; the result clamps to `maxChunkSizeUTF16` = 20, the assumed per-event cap pending the compatibility diagnostic), the modifier-release wait includes Shift, and a failed `CGEvent` creation mid-write throws the typed `AXError.writeIncomplete` instead of silently skipping a chunk. [Source: specs/009-stability-hardening]

`UI/FeedbackPresenter.swift` shows the HUD states (Reading / Thinking / Retrying /
Writing / error). UI must never take keyboard focus, since that would destroy the
target app's selection. Three properties of its `HUDPanel` are load-bearing and
must survive any restyling:

- `.nonactivatingPanel` in the style mask, plus the `canBecomeKey`/`canBecomeMain`
  overrides returning `false`. These are what keep the panel from activating
  Overtype and destroying the selection.
- `isOpaque = false` with `backgroundColor = .clear`, and `.borderless` rather
  than `.hudWindow`/`.utilityWindow`. The rounded shape is drawn solely by
  `HUDAppKitView`'s layer `cornerRadius`; any opaque window background fills the
  corner cut-outs and they render as solid black. Because `.borderless` also
  drops the dark control styling `.hudWindow` forced on the spinner, the panel
  pins `NSAppearance(named: .darkAqua)` explicitly.
- `level = .statusBar`, `collectionBehavior` of `[.canJoinAllSpaces,
  .fullScreenAuxiliary]`, and `hidesOnDeactivate = false`, so a run over a
  fullscreen target still shows feedback.

`Support/Logger.swift` (`Logger.shared`) wraps `os_log` (format `%{public}@`;
`%s` with a Swift String garbles unified-log output) with an `isDebugEnabled`
gate and `sanitizedLog()`, which redacts selected text and model output unless
debug logging is on. The gate reads the persistent `OvertypeDebugLogging`
user default at launch (`defaults write com.github.stn1slv.Overtype
OvertypeDebugLogging -bool true`); enabling it logs a warning AND makes
AppDelegate show a visible launch alert, which is the explicit user warning
Principle V requires. There is deliberately no Settings UI for it. `UI/Settings/SettingsWindow.swift` is the SwiftUI settings
window: all three tabs are functional (as of specs/003-gui-settings). The
General tab manages global preferences (Launch at Login, HUD, typing cadence,
per-app typing overrides) and ends with a read-only `Version` row showing
`Support/AppVersion.swift`'s formatted bundle version, e.g. `1.2.1 (20)`, or
`Unknown` when the metadata is unreadable; it is selectable but deliberately
outside `SettingsViewModel` so it never joins draft state or the save action.
The Providers tab adds/edits/deletes providers,
stores their API keys in the Keychain, and exposes `timeoutSeconds` and
`retryDelaySeconds` as sliders. Both load unclamped from config, since clamping
to the slider range would silently rewrite a deliberate hand-edited value on the
next save; the Actions tab adds/edits/deletes actions
and records global hotkeys via an interactive recorder with conflict detection.
A `SettingsViewModel` handles draft state, slug-based id generation, and atomic
saves through `ConfigStore`.

### Configuration and extension model

- `Config/AppConfig.swift` defines the `Codable` config model; `Config/ConfigStore.swift` loads/persists `~/Library/Application Support/Overtype/config.json`; `Config/DefaultConfig.swift` holds the effective default as an inline JSON string and seeds it on first launch. Decoding is lossy and type-tolerant (specs/009-stability-hardening, contract `contracts/config-tolerance.md`): a wrong-typed defaulted field falls back, an unsalvageable provider/action element is dropped alone, and every fallback/drop is collected via `ConfigDecodingIssues` and surfaced once at launch through `ConfigStore.loadWarningMessage` (issue text names keys and ids only, never values). A whole-file decode failure still backs the file up and falls back to defaults via `loadFailureMessage`. Both Settings entry points share one draft (`SettingsViewModel.shared`), and `reloadFromDisk()` really reads the file, comparing the draft against a `lastLoaded` snapshot so external hand edits are imported instead of overwritten. Note: `Support/Overtype/config.json` is a stale sample, not the packaged default. It is not declared as a package resource in `Package.swift`, is never loaded, and no longer matches the model (it uses `type` instead of `kind` and omits required fields, so it would fail to decode). Treat `DefaultConfig.swift` as the source of truth.
- Config has three parts: `global` (typing speed/HUD), `providers` (id, kind, baseURL, defaultModel, timeoutSeconds, retryDelaySeconds, keychainKey), and `actions` (title, shortcut, providerID, optional model, systemPrompt, userPromptTemplate, temperature, limits, writeStrategy).
- Model resolution order: action-level `model`, then provider `defaultModel`.
- **Adding an automation requires no Swift code**: it is a declarative action record in config. Actions can be added either by editing `config.json` directly or through the in-app Actions editor in Settings (implemented in specs/003-gui-settings).
- **Adding an AI provider** requires exactly three edits: a new case in the provider-kind enum, a new type conforming to `AIProvider`, and one line in `Providers/ProviderRegistry.swift`. `openai` (`OpenAICompatibleProvider`) and `gemini` (`GeminiProvider`, native `generateContent` API) are implemented; `anthropic` and `ollama` are enum cases with stubbed (not yet implemented) branches there. `GeminiProvider` reads its key from the Keychain and sends it in the `x-goog-api-key` header (never in the URL), and maps Gemini safety-blocks/empty candidates to the typed errors `ProviderError.responseBlocked(reason:)` / `.emptyResponse`. [Source: specs/004-gemini-provider]
- API keys live only in the macOS Keychain (`Security/KeychainStore.swift`), referenced by `keychainKey`; they are never written to config, UserDefaults, logs, or the UI.

## Non-negotiable constraints

These come from `.specify/memory/constitution.md` and are enforced in review.
Read that file before any non-trivial change.

- **No clipboard, ever.** `NSPasteboard` and equivalents are forbidden in production code, including as a fallback. `rg NSPasteboard Sources/` must return no match outside comments. Apps that cannot be supported without the clipboard are declared unsupported (terminal emulators are explicitly out of scope).
- **Non-destructive by default.** Never modify the selection until a validated replacement is ready. Abort the write if the target context (frontmost app, pid, or focused element) changed since reading — see the re-check in `ActionEngine`.
- **Privacy.** Selected text and model output must never appear in logs at `info` level or above (debug only, with a user warning). No network calls other than the AI provider the user invoked — no telemetry or update pings.
- **No silent failure.** Every run shows progress and then either success or a specific, typed, human-readable error. Errors are typed values, not strings; runs are cancellable with a hard timeout.
- **Evidence over assumption at the system boundary.** Accessibility/synthetic-event behavior is treated as empirically verified per app in `docs/compatibility.md`, not assumed. Accessibility API return codes are not proof of effect **in either direction**. Any workaround for a platform quirk carries an inline comment naming the quirk and must not be "simplified" without a fresh diagnostic run. (Known real examples: setting selected-text in MS Teams returns success but changes nothing; setting `AXEnhancedUserInterface` on Teams returns `.notImplemented` (-25208) yet takes effect and wakes its dormant tree — never gate on that code; a synthetic event source that inherits held modifiers turns typed characters into shortcuts.)

## Testing discipline

- Pure logic (response sanitization, prompt templating, config decode/migration, shortcut encoding, retry classification and delay clamping) is unit-tested under `Tests/OvertypeTests/`.
- System-boundary code (Accessibility, synthetic events, hotkeys, Keychain) is **not** unit-tested with mocks. It is verified by a manual acceptance procedure run against real apps and recorded in `docs/compatibility.md` before each release.
- `ActionEngine.transformWithRetry` is deliberately `static` and `internal`, not `private`: it touches no instance state, so `TransformRetryTests` drives it with a fake `AIProvider` and asserts the retry behavior itself (exactly one retry, no retry on a non-retryable error, no second request after cancellation). Keep that seam. `run(action:)` around it resolves its provider through `ProviderRegistry.shared` and so stays untestable; do not confuse the two.

## Workflow

The project follows the Spec Kit flow: substantive changes go through
`/specify` → `/plan` → `/tasks` → `/implement`; code outside that flow is limited
to build scripts and docs. Every plan includes a Constitution Check. The PR
checklist (all mandatory): no `NSPasteboard` in `Sources/`; no secret/selected
text/output logged at `info`+; every new boundary workaround commented; unit
tests pass with tests for new pure logic; relevant manual acceptance items
executed and recorded.

Force-unwrapping is forbidden except for unavoidable Core Foundation casts, each
of which must carry a comment.
