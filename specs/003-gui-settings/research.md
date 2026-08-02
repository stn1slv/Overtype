# Research: GUI Configuration Settings

## Dynamic Hotkey Recording and Syncing with `config.json`

- **Decision**:
  Use the pre-integrated `KeyboardShortcuts` package. For each action, we bind a `KeyboardShortcuts.Recorder` to a `KeyboardShortcuts.Name(action.id)`. We observe changes to registered shortcuts via `KeyboardShortcuts.onKeyUp` / `onChange` or by observing `UserDefaults` changes under the KeyboardShortcuts namespace, map the updated shortcut back to `ActionShortcut` (converting modifiers and keycodes), update `AppConfig`, and save to `config.json`.
- **Rationale**:
  Leverages the existing, robust third-party dependency to handle edge cases like modifier keys, system hotkey conflicts, and native recording UI.
- **Alternatives considered**:
  Building a custom SwiftUI key-event interceptor. Rejected because handling modifier combinations and system-level hotkey registration manually is extremely complex and error-prone, and the package is already standard in this repository.

## Settings State Management & Auto-saving

- **Decision**:
  Create a dedicated `SettingsViewModel` conforming to `ObservableObject`. This view model maintains editable draft states for General settings, Providers, and Actions. Saving a provider or action validates the fields, updates the `AppConfig` struct, persists it to `config.json` via `ConfigStore.shared`, and triggers a hotkey registry reload.
- **Rationale**:
  Decouples the SwiftUI views from direct disk operations. Allows form validation (e.g. non-empty prompts, unique IDs) before writing to the config file.
- **Alternatives considered**:
  Binding SwiftUI views directly to `ConfigStore.shared.config` properties. Rejected because it causes immediate disk I/O on every single keystroke in text fields, and provides no opportunity to block invalid configurations.

## Keychain Secret Storage and Provider key sync

- **Decision**:
  Maintain the rule that API keys are stored exclusively in the macOS Keychain using `KeychainStore.shared`. In the Provider detail form, the API key input is a `SecureField`. When the user saves, the key is written directly to the Keychain using the provider's `keychainKey` value (which is a unique string generated during provider creation). The API key field is never bound to any property serialized in `config.json`.
- **Rationale**:
  Ensures absolute compliance with Principle V (Privacy and Secret Handling), which prohibits saving secrets in files or displaying them after entry.
- **Alternatives considered**:
  Saving keys in `UserDefaults` or in `config.json` as encrypted strings. Rejected because they do not utilize the native secure storage provided by the macOS Keychain and violate the project constitution.
