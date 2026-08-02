# Research: Launch at Login

This document resolves unknowns and establishes architectural decisions for the Launch at Login feature.

## 1. Version Increment Strategy

**Decision**: Modify `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Overtype/Resources/Info.plist`.

**Rationale**: The Overtype project is a Swift Package Manager project compiled with a custom `build-app.sh` script. The build script directly copies `Sources/Overtype/Resources/Info.plist` into the generated `.app` bundle. The source of truth for the application's version is this static plist file, not Xcode build settings (since there is no Xcode project file).

**Alternatives considered**: 
- `agvtool`: Not applicable since there is no `xcodeproj`.
- Swift Package Manager versioning: Doesn't translate to app bundle versioning without build tools plugins.

## 2. Managing Login Item State

**Decision**: Use `SMAppService.mainApp` from the `ServiceManagement` framework.

**Rationale**: `SMAppService` was introduced in macOS 13 (Ventura) and is the modern, Apple-recommended API for managing login items, replacing older mechanisms like `SMLoginItemSetEnabled`. Overtype's deployment target is macOS 13+, making this API a perfect fit. It allows synchronous registration, deregistration, and status checks.

**Alternatives considered**:
- `SMLoginItemSetEnabled`: Deprecated in macOS 13.
- `LaunchAgents` plist writing: Unnecessary and complicated for a simple main app launch.

## 3. UI State Management

**Decision**: Create an `ObservableObject` named `LaunchAtLoginManager` that wraps `SMAppService.mainApp.status`.

**Rationale**: SwiftUI requires state to be explicitly tracked to trigger UI updates. By wrapping the `SMAppService` calls in an `ObservableObject` (or checking its state), we can provide a boolean binding to a SwiftUI `Toggle` in the Settings view. If an error is thrown during `register()` or `unregister()`, the manager can update a published error string to satisfy Principle VI (No Silent Failure) and reset the toggle state to match the system.
