# Research: Overtype (Reword)

## 1. Reading Text via Accessibility API

**Decision**: Use `AXUIElementCreateApplication` focused element with retry loops.
**Rationale**: As verified in the build specification, querying `AXUIElementCreateSystemWide` directly fails in Chromium and WebKit apps (e.g., Microsoft Teams). Reading from the application element with `AXManualAccessibility = true` and `AXEnhancedUserInterface = true` is strictly required. A retry loop (12 attempts, 150ms interval) is mandatory for lazily built accessibility trees.
**Alternatives considered**: Relying on standard `NSPasteboard` clipboard reading. Rejected because it violates Constitution Principle I (Clipboard Isolation).

## 2. Writing Text via Synthetic Keyboard Events

**Decision**: Use `CGEvent` with `.privateState` and explicitly clear modifier flags.
**Rationale**: When the global shortcut triggers, the user is still physically holding modifier keys (Cmd/Opt/Ctrl). Emitting standard keyboard events inherits these modifiers, triggering hotkeys instead of typing characters. The event source must be created with `CGEventSource(stateID: .privateState)`, flags must be zeroed, and the application must block typing until all hardware modifiers are released by the user (up to 3 seconds timeout).
**Alternatives considered**: Using `AXUIElementSetAttributeValue` for writing. Rejected as primary because it returns success without actually changing text in Electron apps like Teams. Kept only as an opt-in strategy.

## 3. Global Shortcut Registration

**Decision**: Use Carbon `RegisterEventHotKey` or `KeyboardShortcuts` Swift package.
**Rationale**: `NSEvent.addGlobalMonitorForEvents` only observes and does not consume the keystroke. Real hotkeys that consume the keystrokes are required. We will use the `KeyboardShortcuts` library as it significantly reduces complexity and provides a ready-made SwiftUI shortcut recorder control.
**Alternatives considered**: Manual Carbon API wrappers. Rejected because the `KeyboardShortcuts` library is a standard and robust open-source solution that replaces 200+ lines of low-level C API bridging.

## 4. AI Provider Network Calls

**Decision**: Use `URLSession` with `async/await`.
**Rationale**: Constitution Principle VII strictly mandates no third-party networking libraries. `URLSession` is native, robust, and natively supports modern Swift concurrency.
**Alternatives considered**: Alamofire. Rejected because it introduces an unnecessary third-party dependency.

## 5. Secret Storage

**Decision**: Use Security Framework `kSecClassGenericPassword`.
**Rationale**: API keys must be kept secure. `UserDefaults` or plaintext JSON configuration files are not acceptable for secrets (Constitution Principle V).
**Alternatives considered**: KeychainAccess wrapper library. Rejected as the native Security framework is sufficient for our simple save/read/delete needs.
