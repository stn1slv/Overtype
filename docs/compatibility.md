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

## HUD Transparency Acceptance

`HUDPanel` moved from a `.hudWindow`/`.utilityWindow` style mask to
`[.borderless, .nonactivatingPanel]` with `isOpaque = false`,
`backgroundColor = .clear`, and a pinned `.darkAqua` appearance, so the rounded
corners drawn by `HUDAppKitView`'s layer stop rendering as solid black. Window
presentation is system-boundary work: the properties that matter (focus,
Spaces, fullscreen) cannot be asserted from a unit test.

Verified 2026-08-06 against the ad-hoc local build:

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| H1 | Corners over a real target | Four corners show the app behind, not black | 2026-08-06 pass (reported by the author against a live run) |
| H2 | Focus is never taken | Target app keeps its selection; the replacement is written normally | 2026-08-06 pass (implied by H1: the run completed and wrote its replacement) |
| H3 | Shadow follows the rounded outline | No square shadow around the 300x60 rect; no stale shadow on repeated shows | pending (manual; `hasShadow` confirmed to stay `true` on a borderless panel by direct instantiation, but the drawn result was not inspected) |
| H4 | Over a fullscreen target | HUD still visible; `.canJoinAllSpaces` / `.fullScreenAuxiliary` unaffected by the style-mask change | pending (manual) |
| H5 | On a secondary Space | HUD appears on the active Space | pending (manual) |
| H6 | Light background | Text and spinner legible; spinner still light-colored after `.hudWindow` was dropped | pending (manual) |

H3 through H6 need a human observer. Execute them and replace the `pending`
entries before the next release. H2 is recorded as an inference, not a direct
observation: the focus-critical properties (`.nonactivatingPanel`,
`canBecomeKey`/`canBecomeMain`) are unchanged by this branch.

## Retry Acceptance

`ActionEngine.transformWithRetry` retries a failed provider call once when
`ProviderError.isRetryable` says the failure was transient. Classification, the
delay clamp, and the retry sequencing are pure logic and are covered by
`ProviderErrorRetryTests`, `RetryDelayClampTests`, and `TransformRetryTests`
(`swift test --filter TransformRetryTests`), including cancellation during the
pause. What those cannot cover is a real provider failing for real.

**Status: PENDING** — the retry has not been observed against a live provider.

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| R1 | Live 429 or 5xx | HUD shows `Retrying...`; the second attempt succeeds or a specific error follows | pending |
| R2 | Network dropped mid-run | Retry fires, then a specific network error; selection unchanged | pending |
| R3 | Wrong API key | Error appears immediately, with no retry and no extra delay | pending |
| R4 | Typo'd `baseURL` | Error appears immediately (`.cannotFindHost` is deliberately not retried) | pending |
| R5 | Escape during the retry pause | Run cancels within the pause; selection unchanged; no second request | pending |
| R6 | `showHUD` off | Retry still happens silently; only the final error is shown | pending |
| R7 | Out-of-range `retryDelaySeconds` | A hand-edited `120` logs a clamp warning and waits 60s, not 120s | pending |

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

### Anthropic (native `/v1/messages`)

Pure-logic parsing, reasoning filtering, and error mapping are covered by
`AnthropicProviderTests` (`swift test --filter AnthropicProviderTests`). The live
procedure below is defined in `specs/007-anthropic-provider/quickstart.md`.

**Status: PENDING** — not yet executed against a live key. Run the steps below
with a real Anthropic API key and replace this line with the date and result
before release.

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| A1 | Happy path | Selection replaced by Claude output; Reading → Thinking → Writing HUD | pending |
| A2 | Escape cancels mid-run | Run cancelled; selection unchanged | pending |
| A3 | Context change before write | Write aborted (`contextChanged`); selection unchanged | pending |
| A4 | Missing key | Specific "API Key is missing" error before any network call; selection unchanged | pending |
| A5 | Invalid key | Specific HTTP 401 error; selection unchanged | pending |
| A6 | Unknown model | Specific HTTP 404 error; selection unchanged | pending |
| A7 | Declined response | Specific "blocked" error naming the reason; selection unchanged | pending |
| A8 | Network down | Specific network error; selection unchanged | pending |
| A9 | Reasoning-tier smoke check (model `claude-opus-5`) | Only answer text written; no stray prose in the document | pending |
| A10 | Rate limit retry (429/529) | HUD shows `Retrying...` once, then success or a specific error; selection unchanged | pending |

> **A9 does not verify the reasoning filter, despite appearances.** Overtype
> deliberately sends no `thinking` field, so it cannot request summarised
> reasoning; on the Claude 5 tier `thinking.display` defaults to `"omitted"` and
> reasoning blocks arrive with empty text. A broken allow-list would concatenate
> empty strings and the document would still look right, so A9 passes either way.
> The guarantee that model reasoning never reaches the user's document comes from
> `AnthropicProviderTests`, which feeds synthetic bodies containing non-empty
> `thinking` / `redacted_thinking` / unrecognised block types. Run that suite as
> the gate; treat A9 as an end-to-end smoke check only.

### Ollama (native `/api/chat`, local models)

Executed 2026-08-06 against Ollama `0.32.5` on macOS 15 (Apple silicon), models
`llama3.2` and `deepseek-r1:1.5b`, feature `008-ollama-provider`.

Two different levels of verification are recorded below, and the difference
matters. **Provider-level** means the real `OllamaProvider` was driven against
the running service and the outcome asserted — the network call, the request
body, the parsing, and the typed error are all real, but no text was selected in
a real application. **End-to-end** means the full run through the built bundle:
Accessibility read, provider call, context re-check, and synthetic typing into a
target app. Items still marked `pending (needs manual run)` are the ones that
require a human to select text and press the shortcut; they must be completed
before this feature ships in a release.

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| O1 | Happy path | Selection replaced by local model output; Reading → Thinking → Writing HUD | provider-level PASS (`llama3.2` returned "The cat is sleeping."); end-to-end pending (needs manual run) |
| O2 | Escape cancels mid-run | Run cancelled; selection unchanged | pending (needs manual run) |
| O3 | Settings, empty key field | Provider saves; action runs; no "API Key is missing" error | pending (needs manual run); the keyless code path is covered by `OllamaProviderTests` |
| O4 | `config.json` only | Provider registered and usable after restart | provider-level PASS (decode covered by `AppConfigTests`, registry wiring exercised live); end-to-end pending |
| O5 | Empty Base URL | Request reaches `http://localhost:11434` | PASS (live run used a `ProviderConfig` with no `baseURL`) |
| O6 | Cleartext loopback from the bundle | No App Transport Security block | **PASS**. Probe run from inside `Overtype.app/Contents/MacOS/`, so it read the shipped `Info.plist`: HTTP 200, not `-1022`. **No `NSAppTransportSecurity` key was needed and none was added** |
| O7 | Service not running | Specific error naming the address; no retry | PASS (`serviceUnreachable`, message: "Could not reach the AI service at localhost:59999…" — the address includes the port, so a non-default port is diagnosable); non-retryable asserted in `TransformRetryTests` |
| O8 | Model not installed | Specific error naming the model; no retry | PASS (`modelNotAvailable(model: "nope-xyz")` from a real 404 `{"error":"model 'nope-xyz' not found"}`) |
| O9 | Timeout on a cold large model | Standard timeout error; selection unchanged | pending (needs manual run) |
| O10 | Fully offline run | Run completes | pending (needs manual run — requires disabling every network interface) |
| O11 | Only the configured address is contacted | No other host reached | pending (needs manual run with a network monitor) |
| O12 | Reasoning model writes no reasoning | Only the answer; no reasoning text, no `<think>` markers | **PASS** (provider-level, `deepseek-r1:1.5b`). See the note below |
| O13 | Logs at the default level | No selected text or model output | pending (needs manual run) |
| O14 | Existing providers unaffected | OpenAI/Gemini/Anthropic behave as before | PASS for unit coverage (203 tests, 0 failures); live cloud run pending |
| O15 | Full-size selection at the 5000-character default | Rewritten whole, no silent shortening | pending (needs manual run) |
| O16 | Selection above 6000 characters | Specific error naming the limit; nothing sent; no retry | PASS (`OllamaProviderTests`, `checkInputSize`); end-to-end pending |

> **O12 does verify the reasoning filter here, unlike Anthropic's A9.** Sending
> no `think` field was expected to leave reasoning behaviour to the model, and a
> direct capture confirmed what actually happens on this version: with
> `deepseek-r1:1.5b` and no `think` field, the response carried a **non-empty
> `message.thinking`** ("Okay, so I need to correct the sentence…") alongside a
> clean `message.content`. Layer 1 of the filter — reading `content` only — is
> therefore doing real work against a real payload, not passing vacuously. Layer
> 2 (stripping an inline `<think>` block) did not trigger on this model and is
> covered by unit tests instead; it exists for models and versions that inline
> their reasoning rather than separating it.

> **Wire contract confirmed empirically, not assumed.** The request body Overtype
> sends (`stream: false`, `options.temperature`, `options.num_ctx`) was accepted
> as-is by the running service, and the unknown-model error shape was captured
> from it directly. Note the message wording differs from Ollama's documentation
> (`model 'x' not found`, without the documented "try pulling it first" suffix),
> which is why `isModelNotFound` matches on `"not found"` plus HTTP 404 rather
> than on the full documented sentence.
