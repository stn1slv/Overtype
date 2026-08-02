# Application Compatibility

Because Overtype depends on the macOS Accessibility API (AX) to read and manipulate text natively, it works seamlessly with most native applications but may encounter friction with heavily sandboxed, non-standard, or cross-platform web wrappers that do not expose text fields correctly to VoiceOver and AX systems.

## Supported Applications

- **Native Cocoa Apps**: Apple Notes, Mail, Pages, Messages, Safari, Xcode
- **Electron Apps (with standard AX bindings)**: Slack, Visual Studio Code
- **Chromium Apps**: Google Chrome, Microsoft Edge, Microsoft Teams (PWA / New version)
- **Web Browsers**: Text areas and rich-text editors inside standard browsers.
- **New Outlook** (`com.microsoft.Outlook`, the Chromium/web rewrite): supported, but only with a slowed typing cadence. It applies synthetic keystrokes asynchronously and reorders or drops them under the default fast burst, corrupting the output. The default configuration ships a verified per-app override (one character per event, 10 ms delay); see `appTypingOverrides` in the README. Verified: one character / 10 ms and one character / 20 ms both produce correct output.

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
