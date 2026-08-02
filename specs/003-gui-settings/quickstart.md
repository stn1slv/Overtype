# Quickstart Validation Guide: GUI Configuration Settings

This guide documents the scenarios and verification steps required to prove that the GUI settings interface works correctly end-to-end.

## Prerequisites
- macOS 13 Ventura or later.
- Xcode 15+ or Swift 5.9+ toolchain.
- Access to terminal tools (`jq` is recommended for config inspection).
- Granted Accessibility permission for the local development build of Overtype.

## Setup & Run

1. Build and run the application locally:
   ```bash
   make build
   make run
   ```
2. Open the Settings window by clicking the Overtype menu bar icon and selecting **Settings...**.

## Verification Scenarios

### Scenario 1: General Preferences & App Overrides
1. Navigate to the **General** tab.
2. Toggle the **Launch at login** and **Show HUD** settings.
3. Slide the **Typing Speed Multiplier** to `2.0`.
4. In the **Per-Application Overrides** table:
   - Click **Add Override**.
   - Enter `com.microsoft.Outlook` as the bundle identifier.
   - Set the chunk size to `1` and delay to `10000`.
   - Click **Save**.
5. **Expected Outcome**:
   - Inspect `~/Library/Application Support/Overtype/config.json`.
   - The values under the `"global"` key must match the GUI configuration.
   - Run a test transformation inside Outlook and verify the typing simulation uses the slow cadence override.

### Scenario 2: Provider Configuration & Keychain Storage
1. Navigate to the **Providers** tab.
2. Click **Add Provider**:
   - Set Name to `Custom OpenAI`.
   - Set Base URL to `https://api.example.com/v1`.
   - Set Default Model to `gpt-4o`.
   - Set Timeout to `15.0`.
   - Enter `sk-mockkey12345` in the **API Key** field.
   - Click **Save**.
3. **Expected Outcome**:
   - `config.json` must now list the new provider under the `"providers"` array, with an auto-generated `"id"` of `"custom-openai"`.
   - The JSON entry must contain `"keychainKey": "overtype-custom-openai-key"`. The key `"sk-mockkey12345"` must **NOT** be visible in `config.json`.
   - Verify the secret is saved in the macOS Keychain by running:
     ```bash
     security find-generic-password -s "overtype-custom-openai-key" -w
     ```
     This command must return the entered key: `sk-mockkey12345`.

### Scenario 3: Action Creation & Shortcut Recording
1. Navigate to the **Actions** tab.
2. Click **Add Action**:
   - Set Title to `Proofread Email`.
   - Select `Custom OpenAI` as the provider.
   - Set System Prompt to `Fix all grammar and typos.`
   - Click inside the **Shortcut** recording field and press `Control + Option + Command + P`.
   - Click **Save**.
3. **Expected Outcome**:
   - `config.json` must list the new action under the `"actions"` array with `"id": "proofread-email"`.
   - The shortcut definition in `config.json` must map to the corresponding keyCode and modifier flags.
   - Open a text editor (e.g. TextEdit), type some text, select it, and press `⌃⌥⌘P`. Verify that the HUD shows the transformation progress and replaces the text.

### Scenario 4: Validation & Edge Cases
1. **Shortcut Conflicts**:
   - Add a new action called `Format Code`.
   - Click the shortcut recorder and press `Control + Option + Command + P` (which is already assigned to `Proofread Email`).
   - **Expected Outcome**: The UI must display an inline warning (e.g. "Shortcut already in use by 'Proofread Email'") and block the "Save" action.
2. **Missing API Keys**:
   - Add a provider `NoKeyProvider` without entering an API key.
   - Set up an action linked to `NoKeyProvider` and assign it a hotkey.
   - Press the hotkey on selected text.
   - **Expected Outcome**: The transformation must fail gracefully, and the HUD must display a user-friendly warning: "API Key missing. Please configure it in Settings."
