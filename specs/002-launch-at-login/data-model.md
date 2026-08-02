# Data Model: Launch at Login

The Launch at Login feature does not require persistent disk storage within the application. The source of truth for the setting resides in the macOS operating system.

## Entities

### `LaunchAtLoginManager` (Transient View Model)

This is a SwiftUI-facing object that bridges the native OS `ServiceManagement` state to the view layer.

**Properties**:
- `isEnabled: Bool`
  - *Getter*: Returns `true` if `SMAppService.mainApp.status == .enabled`.
  - *Setter*: Calls `SMAppService.mainApp.register()` if `true`, or `unregister()` if `false`.
- `errorMessage: String?`
  - *State*: Holds a human-readable error description if a registration/deregistration call throws an error.

**State Transitions**:
1. **User toggles ON**:
   - `isEnabled` setter attempts `register()`.
   - On success: System state is now `.enabled`. `errorMessage` is cleared.
   - On failure: `errorMessage` is populated with the error. The toggle should revert because the next read of `isEnabled` will check system status.
2. **User toggles OFF**:
   - `isEnabled` setter attempts `unregister()`.
   - On success: System state is now `.notFound`. `errorMessage` is cleared.
   - On failure: `errorMessage` is populated with the error. 

## Validation Rules

- **Native State Synchronization**: The `isEnabled` getter MUST always evaluate the actual OS state dynamically, rather than relying on a cached boolean, to handle cases where the user modified the login item in macOS System Settings.
