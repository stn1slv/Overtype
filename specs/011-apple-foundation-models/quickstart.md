# Quickstart: Validate the Apple Foundation Models Provider

## Prerequisites

- macOS 27 with Apple Intelligence turned on, and the on-device model downloaded (`fm models` shows `✓ system`).
- Xcode 27 selected: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Automated checks

```bash
make test        # swift test: new mapping, profile, settings and error tests pass
make build
./scripts/build-app.sh
otool -l Overtype.app/Contents/MacOS/Overtype | grep -B3 FoundationModels.framework | grep cmd
# expected: LC_LOAD_WEAK_DYLIB (the app still launches on macOS 13 to 26)
rg NSPasteboard Sources/ Vendor/   # no match outside comments
```

## Manual acceptance (record results in docs/compatibility.md)

Re-grant the Accessibility permission after the rebuild, then add a provider in Settings > Providers: Kind "Apple on-device", model `system`, timeout 60. Base URL and API Key fields must not be shown. Bind a "Fix grammar" action to it.

| ID | Steps | Expected |
|---|---|---|
| Q1 | Select "he go to school yesterday" in TextEdit, press the shortcut | Replaced with a corrected sentence in under 3 s; HUD shows Reading, Thinking, Writing |
| Q2 | Turn Wi-Fi off, repeat Q1 | Same result |
| Q3 | Select a 2,000-word text, press the shortcut, press Escape after 1 s | HUD hides within 1 s, text unchanged |
| Q4 | Run Q1 15 times in a row with TextEdit frontmost | Record whether any run shows "temporarily limited" (research R10) |
| Q5 | Select about 45,000 characters, raise the action's Max Characters to allow it, run | "too long for the on-device model" error at once, text unchanged |
| Q6 | Turn off Apple Intelligence in System Settings, run Q1 | "Turn on Apple Intelligence" error, text unchanged; turn it back on |
| Q7 | Open the Actions editor for the action | No reasoning picker; temperature control present; Automatic caption matches |
| Q8 | Edit an OpenAI provider that has a key, switch Kind to Apple, save | `config.json` record has no `baseURL` and no `keychainKey`; Keychain item removed |
| Q9 | Check `config.json` for the provider | Matches the record in data-model.md |
