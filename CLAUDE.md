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
- Build the distributable `.app` bundle (release build + Info.plist + ad-hoc codesign): `./scripts/build-app.sh` — produces `Overtype.app` in the repo root.
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

The core pipeline lives in `Core/ActionEngine.swift` (`run(action:)`). One run
is a strict sequence, each stage gated on the previous succeeding:

1. `SelectionReader` reads the selected text via the Accessibility API, capturing the source `pid` and focused `AXUIElement`. It delegates to `Support/AXHelpers.swift`, whose `getFocusedElement()` tries five strategies, ending in a depth-first accessibility-tree crawl to find the active text element in Electron, New Outlook, and React Native apps that do not propagate `kAXFocusedUIElementAttribute` (an inline QUIRK WORKAROUND comment marks it). If all five fail *and* the caller passed `wakeDormantTree: true` (only `SelectionReader` does), a sixth escalation runs: `wakeDormantAccessibilityTree` sets `AXEnhancedUserInterface` and `AXManualAccessibility` on the app element, discarding both return codes, then `retryFocusLookup` applies a 2 s AX messaging timeout and retries app-element-first for 24 attempts at 150 ms, checking `Task.checkCancellation()` each pass. `ActionEngine`'s pre-write re-check (step 4) deliberately keeps the single-shot call, so a genuine context change still aborts fast. [Source: specs/005-teams-ax-recovery]
2. The matching provider (from `ProviderRegistry`) performs the AI call. `Providers/OpenAICompatibleProvider.swift` uses `URLSession` async/await; providers conform to the `AIProvider` protocol.
3. `Core/ResponseSanitizer.swift` cleans the model output (pure logic, unit-tested).
4. **Context re-check before writing**: the engine verifies the frontmost `pid` still matches and the focused element is still `CFEqual` to the one read. If either changed, the write is aborted and nothing is modified.
5. `Core/TextWriter.swift` writes the replacement using synthetic keyboard events / the Accessibility API, honoring the action's `writeStrategy` and global typing settings.

`UI/FeedbackPresenter.swift` shows the HUD states (Reading / Thinking / Writing /
error). UI must never take keyboard focus, since that would destroy the target
app's selection.

`Support/Logger.swift` (`Logger.shared`) wraps `os_log` with an `isDebugEnabled`
gate and `sanitizedLog()`, which redacts selected text and model output unless
debug logging is on. `UI/Settings/SettingsWindow.swift` is the SwiftUI settings
window: all three tabs are functional (as of specs/003-gui-settings). The
General tab manages global preferences (Launch at Login, HUD, typing cadence,
per-app typing overrides); the Providers tab adds/edits/deletes providers and
stores their API keys in the Keychain; the Actions tab adds/edits/deletes actions
and records global hotkeys via an interactive recorder with conflict detection.
A `SettingsViewModel` handles draft state, slug-based id generation, and atomic
saves through `ConfigStore`.

### Configuration and extension model

- `Config/AppConfig.swift` defines the `Codable` config model; `Config/ConfigStore.swift` loads/persists `~/Library/Application Support/Overtype/config.json`; `Config/DefaultConfig.swift` holds the effective default as an inline JSON string and seeds it on first launch. Note: `Support/Overtype/config.json` is a stale sample, not the packaged default. It is not declared as a package resource in `Package.swift`, is never loaded, and no longer matches the model (it uses `type` instead of `kind` and omits required fields, so it would fail to decode). Treat `DefaultConfig.swift` as the source of truth.
- Config has three parts: `global` (typing speed/HUD), `providers` (id, kind, baseURL, defaultModel, keychainKey), and `actions` (title, shortcut, providerID, optional model, systemPrompt, userPromptTemplate, temperature, limits, writeStrategy).
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

- Pure logic (response sanitization, prompt templating, config decode/migration, shortcut encoding) is unit-tested under `Tests/OvertypeTests/`.
- System-boundary code (Accessibility, synthetic events, hotkeys, Keychain) is **not** unit-tested with mocks. It is verified by a manual acceptance procedure run against real apps and recorded in `docs/compatibility.md` before each release.

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
