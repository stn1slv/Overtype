# Overtype — Project Plan (Memory)

Cumulative, project-level implementation plan, assembled by archiving merged
feature plans. It follows the section ordering of
`.specify/templates/plan-template.md`. Each entry carries a `[Source: …]` tag.
This reflects the *implemented* state, not aspirational design.

Bootstrapped 2026-08-02 from the first archived feature (Gemini Model Support).

---

## Technical Context (baseline)

- **Language/Stack**: Swift 5.9, macOS 13+, SwiftUI, `URLSession` async/await.
- **Build**: Swift Package Manager; `Makefile` wraps `build|test|lint|format|run`.
- **Storage**: `~/Library/Application Support/Overtype/config.json` + macOS Keychain.
- **Testing**: XCTest for pure logic; manual acceptance for system-boundary code,
  recorded in `docs/compatibility.md`.
- **Toolchain note**: `swift test` requires Xcode's XCTest. If `xcode-select -p`
  points at CommandLineTools, run with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` or
  `sudo xcode-select -s /Applications/Xcode.app`.

## Primary Dependencies

- `sindresorhus/KeyboardShortcuts` (v1.15.0; global shortcut registration and
  the settings-window shortcut recorder).
- `ServiceManagement` — Apple system framework (`SMAppService`), added by
  Launch at Login for login-item registration. Not a third-party package.

## Project Structure (services / modules)

```text
Sources/Overtype/
├── Config/            # AppConfig, ConfigStore, DefaultConfig
├── Core/              # ActionEngine, ResponseSanitizer, TextWriter
├── Providers/         # AIProvider protocol, ProviderRegistry, provider types
├── Security/          # KeychainStore
├── Support/           # AXHelpers, PermissionManager, Logger
└── UI/                # FeedbackPresenter, Settings/*
```

### Feature increments

#### Overtype Foundation `[Source: specs/001-overtype]`

- **Scope**: Established the entire product — a native macOS menu bar utility
  (`LSUIElement`, no Dock icon) that transforms selected text via AI without the
  clipboard, extensible by configuration rather than code.
- **Core loop**: Accessibility API to read the selection; `CGEvent` synthetic
  keyboard events to write the replacement; non-destructive abort on focus loss.
- **Domains created**: `Core/` (ActionEngine, ResponseSanitizer, TextWriter),
  `Providers/` (AIProvider protocol, ProviderRegistry, OpenAI-compatible provider),
  `Config/`, `Security/` (Keychain), `Support/` (AXHelpers, Logger), `UI/` (HUD).
- **Dependencies**: native frameworks (AppKit, SwiftUI, Security, Accessibility,
  URLSession) plus the optional `sindresorhus/KeyboardShortcuts` SPM package for
  hotkey registration.
- **Performance goal**: AI text-replacement workflow < 3 seconds total; instant
  HUD feedback.
- **Constitution check (archived)**: Passed — I (clipboard isolation), II
  (non-destructive), IV (configuration over code), V (privacy/secrets), VII
  (native stack) all verified.

#### GUI Configuration Settings `[Source: specs/003-gui-settings]`

- **Approach**: Replace manual `config.json` editing with a native SwiftUI
  settings window of three functional tabs (General, Providers, Actions). No new
  dependency (reuses `KeyboardShortcuts` for the hotkey recorder).
- **New/edited modules**: `UI/Settings/SettingsWindow.swift` plus
  `GeneralTab.swift`, `ProvidersTab.swift`, `ActionsTab.swift`; a
  `SettingsViewModel` managing editable draft state, slug-based id generation,
  shortcut-conflict checking, and atomic saves via `ConfigStore`;
  `Core/HotkeyManager.swift` for dynamic re-registration.
- **Persistence**: still `config.json` + Keychain under the hood; the GUI is a
  front end. Config loads at startup and when the window becomes active.
- **Testing**: `Tests/OvertypeTests/SlugGenerationTests.swift` (id generation /
  uniqueness) and `AppConfigTests.swift` (encode/decode). Constitution PASS on
  I, II, V, VI, VII, VIII.

#### Launch at Login `[Source: specs/002-launch-at-login]`

- **Approach**: Add a "Launch at Login" toggle backed by Apple's native
  `ServiceManagement` framework (`SMAppService.mainApp`), the recommended
  macOS 13+ API for login items. No third-party dependency.
- **New module**: `Sources/Overtype/Support/LaunchAtLoginManager.swift` — an
  `ObservableObject` wrapping `SMAppService.mainApp.status`, exposing a boolean
  binding for a SwiftUI `Toggle`, publishing an error string and reverting the
  toggle to the system state on `register()`/`unregister()` failure (Principle VI).
- **Edits**: settings view (`UI/`) gains the checkbox; `Resources/Info.plist`
  minor version bumped.
- **Storage**: none custom — login-item state is owned by macOS.
- **Verification**: manual acceptance (system boundary), no mocks (Principle VIII).

#### Gemini Model Support `[Source: specs/004-gemini-provider]`

- **Approach**: Dedicated native Gemini provider calling the Gemini
  `generateContent` REST API. Honors the constitution's three-edit extension rule
  (Principle IV): one enum case, one provider type, one registry line.
- **New module**: `Sources/Overtype/Providers/GeminiProvider.swift` — conforms to
  `AIProvider`; `transform(_:)` builds the request and maps failures; pure static
  helpers `endpointURL(base:model:)`, `parseResponseText(from:)`,
  `extractText(from:)`.
- **Edits**: `Config/AppConfig.swift` (`ProviderKind.gemini = "gemini"`);
  `Providers/AIProvider.swift` (new `ProviderError` cases `responseBlocked(reason:)`,
  `emptyResponse`); `Providers/ProviderRegistry.swift` (one line wiring
  `.gemini` → `GeminiProvider`).

#### Reliable Selection Reading / Dormant AX Trees `[Source: specs/005-teams-ax-recovery]`

- **Approach**: A bounded recovery path inside the existing selection read,
  entered **only** after all five existing lookup strategies fail. No new files,
  no new dependency, no configuration surface.
- **Edits**: `Sources/Overtype/Support/AXHelpers.swift` —
  `getFocusedElement(wakeDormantTree: Bool = false)` plus two private helpers,
  `wakeDormantAccessibilityTree(appElement:)` and `retryFocusLookup(appElement:)`;
  `Sources/Overtype/Core/SelectionReader.swift` — the single opt-in call site
  (`wakeDormantTree: true`).
- **Recovery sequence**: set `AXEnhancedUserInterface` and
  `AXManualAccessibility` to true on the target app element, discarding both
  returned `AXError` values; `AXUIElementSetMessagingTimeout(2.0)` on the app
  element and a fresh system-wide element; then 24 attempts at 150 ms,
  `try Task.checkCancellation()` first in each iteration, querying the app
  element's focused element before the system-wide one. An element with a
  non-empty selection returns immediately; a selection-less element is kept as a
  fallback candidate while retries continue. Constants live in
  `AXHelpers.recoveryAttempts` / `recoveryMessagingTimeoutSeconds`.
- **Design decision — recovery is read-path only.** `ActionEngine`'s pre-write
  context re-check deliberately keeps single-shot behavior: by write time the
  tree is provably warm, and Principle II requires a changed context to abort
  fast rather than after seconds of retries.
- **Verification**: system-boundary code, so no mock-based unit tests
  (Principle VIII). Validated by `specs/005-teams-ax-recovery/quickstart.md`
  scenarios B–E, recorded in `docs/compatibility.md`. **Manual acceptance is
  PARTIAL**: the single-press cold-Teams retest at 24 attempts, the native-app
  fast-path check, the failure-timing/Escape scenario, and the regression sweep
  are outstanding (tasks T007, T009, T011, T013).

### Configuration

- No configuration is added by the dormant-tree recovery: it is automatic and
  invisible, and its constants are compile-time values bound to the tested
  configuration (deliberately not exposed, to avoid untested combinations).
- New provider kind wire value `"gemini"` in `config.json`. A Gemini provider
  block may omit `baseURL` (defaults to the Google v1beta base). The shipped
  default config is unchanged; Gemini is enabled via a documented README recipe.
- No new environment variables.

### Integration Contracts

- **Gemini `generateContent`** (only endpoint contacted for a Gemini run):
  `POST {base}models/{model}:generateContent`, auth via `x-goog-api-key` header
  (never in the URL). Request maps `systemInstruction`, `contents`, and
  `generationConfig.temperature`. Success reads
  `candidates[0].content.parts[*].text`. Contract detail:
  `specs/004-gemini-provider/contracts/gemini-generatecontent.md`.
- Failure mapping: non-200 → `.apiError` (reusing OpenAI-style message
  extraction); `URLError` → `.timeout` / `.cancelled` / `.networkError`;
  `promptFeedback.blockReason` / `finishReason == "SAFETY"` / no candidates →
  `.responseBlocked(reason:)`; empty text → `.emptyResponse`; malformed →
  `.invalidResponse`.

### Testing Strategy

- Unit tests (`Tests/OvertypeTests/GeminiProviderTests.swift`): success parsing,
  multi-part concatenation, endpoint URL construction, and all failure mappings.
- `Tests/OvertypeTests/AppConfigTests.swift`: `kind: gemini` config decode.
- Manual acceptance (`specs/004-gemini-provider/quickstart.md`, A1–A8) recorded
  in `docs/compatibility.md`. **Live acceptance is PENDING** and gates release.
- Dormant-tree recovery adds **no** unit tests by design (system-boundary code,
  no new pure logic); the existing suite must stay green. Its verification is the
  manual procedure above.

## Known Gotchas (from research)

- **A dormant accessibility tree is not a permission problem.** After Microsoft
  Teams restarts, every AX query returns `noValue` in ~12 ms and the tree stays
  dormant until an assistive client announces itself. Diagnose this before
  suspecting a code regression or a revoked Accessibility grant.
- **AX return codes are not evidence in either direction.** Setting
  `AXEnhancedUserInterface` on Teams returns `.notImplemented` (-25208) yet takes
  effect (read-back flips to true and the tree activates). This is the mirror of
  the known Teams write quirk, where a set call returns success and changes
  nothing. Never gate on the returned `AXError` at these sites.
- **`AXManualAccessibility` covers a different app family.** Teams rejects it
  (`attributeUnsupported`); Electron apps (VS Code, Claude desktop) honor it.
  Setting both flags covers both families at no cost.
- **Wake flags have side effects, so they stay on the failure path.**
  `AXEnhancedUserInterface` is the flag VoiceOver sets and has historically
  caused window-resize/zoom glitches in some Electron apps. It is set only for
  apps that are already unusable with Overtype, at most once per run. The state
  persists in the target process until that app restarts; no cleanup is
  attempted, which is the intended assistive-client behavior.

- **Endpoint colon must not be percent-encoded.** The `:generateContent` action
  suffix is built by string concatenation, not `URL.appendingPathComponent`,
  which would encode the colon and break the request.
- **Key belongs in a header, not the URL.** The API key is sent as
  `x-goog-api-key`; putting it in a `?key=` query parameter risks leaking the
  secret into any URL-based logging (Principle V).

## Constitution Check (archived)

Gemini Model Support was verified against all eight principles at plan, PR, and
converge stages with no violations. Outstanding: the manual acceptance
(Principle VIII / PR checklist item 5) must be executed before release.

### Revision: Archival 2026-08-02

- Reason: Archived the foundational feature `specs/001-overtype` (added the
  "Overtype Foundation" increment above). No new dependency beyond the baseline
  already recorded; content reflects the implemented base architecture.

### Revision: Archival 2026-08-02 (Launch at Login)

- Reason: Archived `specs/002-launch-at-login`. Added the Launch at Login
  increment and the `ServiceManagement` system-framework dependency.

### Revision: Archival 2026-08-02 (GUI Configuration Settings)

- Reason: Archived `specs/003-gui-settings`. Added the Settings GUI increment and
  pinned the `KeyboardShortcuts` dependency version (1.15.0). No new dependency.

### Revision: Archival 2026-08-04 (Reliable Selection Reading / Dormant AX Trees)

- Reason: Archived `specs/005-teams-ax-recovery`. Added the dormant-tree recovery
  increment, its four research gotchas, and a "no configuration added" note. No
  new dependency and no new module — the change is contained in
  `Support/AXHelpers.swift` with a one-line opt-in from `Core/SelectionReader.swift`,
  so the Project Structure tree is unchanged. Manual acceptance is recorded as
  PARTIAL (T007, T009, T011, T013 outstanding).
