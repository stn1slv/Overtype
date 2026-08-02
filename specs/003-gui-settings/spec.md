# Feature Specification: GUI Configuration Settings

**Feature Branch**: `003-gui-settings`

**Created**: August 2, 2026

**Status**: Completed

**Input**: User description: "let's implement gui configuration settings instead of config.json"

## Clarifications

### Session 2026-08-02

- Q: How should unique identifiers (id) for new AI providers and actions be generated when they are created via the GUI settings? → A: Auto-generate a slug from the user-entered Title (e.g., "translate-french"), showing it as read-only and appending a numeric suffix if a conflict exists.
- Q: How should the application handle external modifications to the config.json file while the app is running? → A: Only load the configuration on application startup and when the settings GUI window is opened/made active.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Manage AI Providers and Credentials (Priority: P1)

As an Overtype user, I want to add and configure OpenAI-compatible AI providers and input their API keys through a clean graphical user interface, so that I do not have to write raw JSON configuration or deal with manual Keychain command-line tools.

**Why this priority**: AI providers are the backbone of all text transformations. Providing an intuitive interface to configure them and enter secrets securely is critical for usability and security.

**Independent Test**:
Can be fully tested by creating a new OpenAI provider, setting its properties and saving, then invoking an action linked to it to verify connectivity.

**Acceptance Scenarios**:

1. **Given** the settings window is open, **When** I navigate to the "Providers" tab, **Then** I see a list of configured providers and an option to add a new provider.
2. **Given** I am adding or editing a provider, **When** I edit the base URL, default model, timeout, and then enter an API key and click "Save", **Then** the provider properties are written to `config.json` (with no API key in the JSON file), and the API key is securely saved to the macOS Keychain under the specified keychain key name.
3. **Given** a provider is configured, **When** I delete the provider, **Then** it is removed from the settings list and the `config.json` file, and its corresponding API key is deleted from the macOS Keychain.

---

### User Story 2 - Manage Actions/Automations and Shortcuts (Priority: P1)

As an Overtype user, I want to create, edit, disable, and delete custom text automations (actions) and assign global hotkeys to them using an interactive GUI, so that I can easily customize my writing assistant workflows.

**Why this priority**: The value of Overtype lies in the ability to run customized prompts using dynamic hotkeys. Hand-editing hotkey modifiers and prompt strings in JSON is highly error-prone.

**Independent Test**:
Can be tested by creating a new action called "Translate to French", assigning a hotkey (e.g., `Ctrl+Option+Cmd+F`), setting a system prompt, and verifying it successfully appears in the menu bar and triggers correctly.

**Acceptance Scenarios**:

1. **Given** the settings window is open, **When** I navigate to the "Actions" tab, **Then** I see a list of all current actions with their status (enabled/disabled), titles, and assigned shortcuts.
2. **Given** I click "Add Action" or choose to edit an existing action, **When** I edit the title, system prompt, temperature, character limits, select an AI provider, and click a shortcut recording field to type a hotkey, **Then** all inputs are validated, the shortcut is updated, and the new configuration is persisted to `config.json` immediately.
3. **Given** an action has an active global shortcut, **When** I disable the action via a toggle in the list, **Then** the global hotkey is immediately unregistered, and the action will not run if the hotkey is pressed.

---

### User Story 3 - Adjust General Preferences and Typing Cadence (Priority: P2)

As an Overtype user, I want to control the app's global behavior (such as showing the HUD or adjusting the synthetic typing speed) and configure application-specific overrides via the GUI, so that the utility behaves correctly across different word processors and editors.

**Why this priority**: Different applications handle synthesized keystrokes at different rates. If a user notices typing errors in an app like Outlook, they need a simple GUI option to adjust the typing delay and chunk size.

**Independent Test**:
Can be tested by changing the global typing speed multiplier or adding an override for a specific application in the settings, then running a text transformation inside that application and confirming the typing cadence matches the new configuration.

**Acceptance Scenarios**:

1. **Given** the settings window is open, **When** I navigate to the "General" tab, **Then** I can toggle "Launch at login", "Show HUD", and adjust the "Typing Speed Multiplier" slider.
2. **Given** a change is made to a global preference (e.g., toggling HUD visibility), **When** I invoke a text transformation, **Then** the application immediately applies the updated preference without requiring a restart.

---

### Edge Cases

- **Invalid Shortcut Modifiers**: If a user attempts to record a shortcut that contains no modifier keys (e.g., just the letter 'A' by itself), the recorder must block this to prevent overriding normal typing.
- **Empty Prompts**: If a user attempts to save an action with an empty system prompt or user prompt template, the interface must show a validation error.
- **Missing API Keys**: If an action is invoked for a provider that has no API key stored in the Keychain, the application should show a human-readable HUD error informing the user that the API key is missing, directing them to the settings window.
- **Malformed config.json**: If the user has manually edited `config.json` into a state that cannot be parsed, the app must fall back to default configurations gracefully, and the GUI settings window should offer to reset the configuration to defaults.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The settings window MUST display three tabbed views: "General", "Providers", and "Actions".
- **FR-002**: All configuration updates made in the GUI MUST be auto-saved and synchronized back to the underlying `config.json` file immediately, except for API keys which MUST be saved securely to the macOS Keychain. The application MUST load the configuration from `config.json` at startup and whenever the settings window becomes active; live file system monitoring for external changes to `config.json` is not required.
- **FR-003**: The Providers Tab MUST allow users to view, add, modify, and delete provider configurations including ID, provider kind, base URL, default model, and timeout duration. The provider ID is auto-generated as a slug from the provider name, shown as read-only, with a numeric suffix appended if a conflict exists.
- **FR-004**: The Actions Tab MUST allow users to view, add, modify, and delete text automations (actions) including title, system prompt, temperature, provider, model override, character limit, and write strategy. The action ID is auto-generated as a slug from the title, shown as read-only, with a numeric suffix appended if a conflict exists.
- **FR-005**: The Actions Tab MUST include an interactive shortcut recorder that allows users to register or change the hotkey for any action. Shortcuts must support conflict detection. If a conflict is detected, the application MUST display an inline warning and block saving or registering the shortcut until the conflict is resolved by the user.
- **FR-006**: The General Tab MUST allow configuring global typing cadence settings (typing speed multiplier, typing chunk size, typing delay, and HUD visibility) and per-application overrides. This includes a list-based editor where users can add or remove application bundle identifiers (or choose from running applications) and set custom typing delays and chunk sizes for each application.

### Key Entities

- **GeneralConfig**: Represents the global behavior settings of the application.
- **ProviderConfig**: Represents connection parameters for an OpenAI-compatible AI inference endpoint.
- **ActionConfig**: Represents a single text automation workflow, mapping a custom hotkey and prompts to an AI provider.
- **Keychain Secret**: An API key securely bound to a specific `ProviderConfig`'s `keychainKey`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can add a new custom text automation, configure its prompts, and assign a hotkey in under 45 seconds using only the GUI.
- **SC-002**: 100% of API keys configured through the GUI must be stored exclusively in the macOS Keychain and must never appear in `config.json` or in-app diagnostic logs.
- **SC-003**: 100% of configuration changes made via the settings interface must take effect immediately without requiring an application restart.
- **SC-004**: If a hotkey conflict is detected during shortcut recording, the user must be notified immediately and prevented from registering duplicate shortcuts.

## Assumptions

- We will continue to load and save to the local `config.json` under the hood as our persistent store, ensuring that advanced users can still view or migrate the configuration file if desired.
- Modifying settings through the GUI will dynamically re-register system-wide hotkeys using the existing `KeyboardShortcuts` framework.
- The default configurations (e.g., the default "Fix grammar" action and default OpenAI provider) will be pre-populated in the GUI on first launch if `config.json` does not exist.
