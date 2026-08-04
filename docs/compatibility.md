# Application Compatibility

Because Overtype depends on the macOS Accessibility API (AX) to read and manipulate text natively, it works seamlessly with most native applications but may encounter friction with heavily sandboxed, non-standard, or cross-platform web wrappers that do not expose text fields correctly to VoiceOver and AX systems.

## Supported Applications

- **Native Cocoa Apps**: Apple Notes, Mail, Pages, Messages, Safari, Xcode
- **Electron Apps (with standard AX bindings)**: Slack, Visual Studio Code
- **Chromium Apps**: Google Chrome, Microsoft Edge, Microsoft Teams (PWA / New version)
- **Web Browsers**: Text areas and rich-text editors inside standard browsers.
- **New Outlook** (`com.microsoft.Outlook`, the Chromium/web rewrite): supported, but only with a slowed typing cadence. It applies synthetic keystrokes asynchronously and reorders or drops them under the default fast burst, corrupting the output. The default configuration ships a verified per-app override (one character per event, 10 ms delay); see `appTypingOverrides` in the README. Verified: one character / 10 ms and one character / 20 ms both produce correct output.

### Dormant accessibility trees (Microsoft Teams, VS Code class)

Verified 2026-08-02 (live diagnostic against Teams `com.microsoft.teams2`, process restarted the same day):

- After the Teams process restarts, its accessibility tree is **dormant**: every AX query (focused element, focused window, main window) returns `noValue` immediately, so a single-shot lookup fails with `noFocusedElement` in ~12 ms. The tree stays dormant until an assistive client announces itself.
- Setting `AXEnhancedUserInterface = true` on the Teams application element wakes the tree. **The set call returns `.notImplemented` (-25208) yet takes effect** (read-back flips to true; reads started succeeding with no other change). Do not treat the AX return code as evidence in either direction; this is the read-side mirror of the known Teams write quirk (set-selected-text returns success while changing nothing; see the constitution, Principle III rationale).
- `AXManualAccessibility` is the Electron equivalent: accepted by VS Code and Claude desktop, rejected by Teams (`attributeUnsupported`).
- Overtype therefore performs a bounded recovery when the normal lookup finds nothing: set both wake flags (ignoring their return codes), apply a 2 s AX messaging timeout, and retry the app-element-first lookup up to 24 times at 150 ms intervals (ordering and interval validated by the 2026-07-31 axprobe series; the attempt count was raised from 12 after the 2026-08-02 cold-Teams acceptance run showed the selection attribute populates only ~2.7 s after the wake). The recovery runs only on the failure path, so well-behaved apps see no change; the wake state persists until the target app restarts.

Manual acceptance for this feature (`specs/005-teams-ax-recovery/quickstart.md`):

| Scenario | Expected | Result |
|----------|----------|--------|
| B. Cold Teams restart, first run recovers (twice) | Success within ~3 s of a warm run | 2026-08-02 partial: recovery triggered and woke the cold tree (old build failed instantly in the same state); with the 12-attempt window the first press ended in the clean `cannotReadSelectedText` error and the second press succeeded instantly. Window raised to 24 attempts; single-press cold retest pending |
| C. Warm Teams / Outlook / native app unchanged | No recovery log lines, unchanged latency | 2026-08-02 pass for warm Teams and Outlook (instant reads, no recovery lines); native app pending |
| D. Nothing selected fails fast; Escape cancels recovery | Same errors; cancel < 1 s | pending |
| E. Regression sweep (Outlook, native, VS Code) | Matches existing entries | pending |

## Unsupported / Problematic Applications

- **Terminal Emulators**: iTerm2, Terminal.app, Alacritty. (Terminals don't select and manage text via standard macOS AX text ranges).
- **Custom JVM Apps**: Some legacy Java GUI applications.
- **Remote Desktop Clients**: Citrix Workspace, Microsoft Remote Desktop (the text input occurs on a remote host, so AX reading won't capture local text).

## Troubleshooting

If an application is rejecting input:
1. Ensure the app has active focus.
2. Ensure you have granted Accessibility permission in System Settings.
3. Try increasing `typingDelayMicroseconds` (or lowering `typingSpeedMultiplier`) in `config.json` if characters are being dropped during insertion (especially common in heavily-scripted web rich-text editors like Google Docs).
4. If a specific app drops or **reorders** characters (a race between the keystroke burst and the app's async input), add a per-app override under `appTypingOverrides` keyed by its bundle identifier, using a small `typingChunkSize` (for example `1`) and a larger `typingDelayMicroseconds`. When you run an action, the target app's bundle id is written to the log (the `Effective typing config ... bundleID ...` line, visible in Console.app under subsystem `com.github.stn1slv.Overtype`); you can also find it with `osascript -e 'id of app "App Name"'`.

## Version Display Acceptance

The Settings > General tab shows the version the running build declares about
itself, and `scripts/build-app.sh` stamps that version into the bundle. Bundle
reading, the settings row and the shell stamping are system-boundary work, so
they are verified by the procedure in
`specs/006-settings-version-display/quickstart.md`, not by mocks. The formatting
rules are pure logic and are covered by `AppVersionTests`
(`swift test --filter AppVersionTests`).

Verified 2026-08-04 against the ad-hoc local build at commit count 20:

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| 2 | Stamped release build | `OVERTYPE_VERSION=1.2.1 ./scripts/build-app.sh` declares `1.2.1` / build `20` | 2026-08-04 pass |
| 3 | Signature and repo invariants | `codesign --verify` passes; tracked `Info.plist` byte-identical after a build; `CFBundleIdentifier`, `LSUIElement`, `LSMinimumSystemVersion` unchanged | 2026-08-04 pass (plist checksum identical before/after) |
| 4 | Unstamped local build | Falls back to the checked-in `1.2.1`; build is still the commit count | 2026-08-04 pass |
| 5 | General tab shows the version | Labelled `Version` row at the end of the tab, value `1.2.1 (20)`, not editable, unaffected by Save | pending (manual, needs a launched app) |
| 6 | Existing General tab settings unaffected | Launch at login, cadence, HUD, overrides all load/change/save as before | pending (manual) |
| 7 | Appearance and long values | Legible in Light and Dark; `1.3.0-beta.1` shown in full without clipping | pending (manual) |
| 8 | Unknown path | With `CFBundleShortVersionString` deleted, the tab opens and shows `Version Unknown` | pending (manual; covered automatically by `AppVersionTests`) |
| 9 | Zero network activity | No outbound connections while the General tab is displayed | pending (manual) |

Rows 5 through 9 require a launched application and a human observer. Execute them
and replace the `pending` entries before the next release.

## Provider Acceptance

System-boundary provider behavior (a live network call) is verified by a manual
acceptance procedure, not by mocks. Record the outcome here before each release.

### Google Gemini (native `generateContent`)

Pure-logic parsing and error mapping are covered by `GeminiProviderTests`
(`swift test --filter GeminiProviderTests`). The live procedure below is defined
in `specs/004-gemini-provider/quickstart.md`.

**Status: PENDING** — not yet executed against a live key. Run the steps below
with a real Gemini API key and replace this line with the date and result before
release.

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| A1 | Happy path | Selection replaced by Gemini output; Reading → Thinking → Writing HUD | pending |
| A2 | Escape cancels mid-run | Run cancelled; selection unchanged | pending |
| A3 | Context change before write | Write aborted (`contextChanged`); selection unchanged | pending |
| A4 | Missing key | Specific "API Key is missing" error; selection unchanged | pending |
| A5 | Invalid key | Specific API error (server message); selection unchanged | pending |
| A6 | Unknown model | Specific API error (unknown model); selection unchanged | pending |
| A7 | Safety block | Specific "blocked" error with reason; selection unchanged | pending |
| A8 | Network down | Specific network error; selection unchanged | pending |
