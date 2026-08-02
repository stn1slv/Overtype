# Overtype — Changelog

## Merged Features Log

### GUI Configuration Settings — 2026-08-02
**Branch:** 003-gui-settings
**Spec:** specs/003-gui-settings

_Note: FR/SC IDs renumbered to FR-029–FR-034 / SC-015–SC-018 in memory `spec.md`
to continue the sequence._

**What was added:**
- US1 (P1): GUI management of OpenAI-compatible providers and Keychain API keys.
- US2 (P1): GUI creation/editing of actions with an interactive hotkey recorder
  and conflict detection.
- US3 (P2): General preferences (Launch at Login, HUD, typing cadence) and
  per-app typing overrides. Slug-based auto-generated ids; immediate apply.

**New Components:**
- `UI/Settings/` — `SettingsWindow`, `GeneralTab`, `ProvidersTab`, `ActionsTab`;
  a `SettingsViewModel`; `Tests/OvertypeTests/SlugGenerationTests.swift`.

**Tasks Completed:** 22/22 tasks.

### Gemini Model Support — 2026-08-02
**Branch:** 004-gemini-provider
**Spec:** specs/004-gemini-provider

**What was added:**
- US1 (P1): run an action against a native Google Gemini model end to end.
- US2 (P1): enable Gemini by configuration only (documented recipe), no rebuild.
- US3 (P2): specific typed errors for Gemini failures (missing/invalid key,
  unknown model, quota, network, empty/safety-blocked), selection always preserved.

**New Components:**
- `Sources/Overtype/Providers/GeminiProvider.swift` (native `generateContent` client).
- `ProviderKind.gemini` enum case; `ProviderError.responseBlocked(reason:)` and
  `ProviderError.emptyResponse`; one `ProviderRegistry` wiring line.
- Docs: README Gemini recipe, `docs/privacy.md` and `docs/compatibility.md` updates.

**Tasks Completed:** 20/21 tasks (T020 live manual acceptance pending before release).

### Launch at Login — 2026-08-01
**Branch:** 002-launch-at-login
**Spec:** specs/002-launch-at-login

_Note: archived on 2026-08-02. FR/SC IDs renumbered to FR-024–FR-028 /
SC-011–SC-014 in memory `spec.md` to continue the sequence._

**What was added:**
- US1 (P1): enable launch at login via a settings checkbox (registers a macOS login item).
- US2 (P1): disable launch at login (deregisters the login item).
- UI reflects the true OS login-item state; failures surface a human-readable
  error and revert the checkbox. Application minor version incremented.

**New Components:**
- `Sources/Overtype/Support/LaunchAtLoginManager.swift` (wraps `SMAppService.mainApp`).
- Dependency: `ServiceManagement` system framework.

**Tasks Completed:** 7/7 tasks.

### Overtype Foundation — 2026-07-31
**Branch:** 001-overtype
**Spec:** specs/001-overtype

_Note: archived on 2026-08-02, after 004; this is the foundational feature that
established the product. Its FR/SC IDs were renumbered to FR-014–FR-023 /
SC-006–SC-010 in memory `spec.md` to avoid collision with 004's already-archived
IDs._

**What was added:**
- US1 (P1): grammar correction in chat apps via global shortcut, clipboard untouched.
- US2 (P2): tone adjustment through additional config-defined actions.
- US3 (P3): local AI model support for privacy.
- The clipboard-free read/write core loop (Accessibility + `CGEvent`),
  configuration-driven actions/providers, Keychain secret storage, HUD feedback,
  response sanitization, cancellation, and typed error handling.

**New Components:**
- Full initial codebase: `Core/`, `Providers/` (AIProvider, ProviderRegistry,
  OpenAI-compatible provider), `Config/`, `Security/`, `Support/`, `UI/`.
- Dependency: `sindresorhus/KeyboardShortcuts` (hotkey registration).

**Tasks Completed:** 28/29 tasks.
