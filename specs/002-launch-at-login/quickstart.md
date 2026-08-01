# Quickstart Validation Guide: Launch at Login

This guide describes how to validate the Launch at Login feature manually, fulfilling the manual acceptance testing requirement for system boundary interactions.

## Setup

1. Build and run the app bundle using the Makefile:
   ```bash
   make run
   ```

## Scenario 1: Verify Version Increment

1. Launch Overtype.
2. In the menu bar, click the Overtype icon to open the menu.
3. Observe the version number in the menu (if present) or right-click the `Overtype.app` bundle in Finder and select "Get Info".
4. **Expected Outcome**: The version should be `1.1` (or whatever the next minor version is) and the build number should be incremented.

## Scenario 2: Enable Launch at Login

1. Build the app using `make build-app`.
2. **IMPORTANT**: Copy the generated `Overtype.app` bundle into your `/Applications` directory. `SMAppService` relies on accurate ad-hoc code signing and bundle location, and running it directly from the dev repository can cause it to silently fail or throw permission errors.
3. Launch Overtype from `/Applications`.
4. Click the Overtype menu bar icon.
5. Select **Settings**.
6. Locate the **Launch at login** checkbox. It should initially reflect your system's current state (likely unchecked).
7. Check the box.
8. Open macOS **System Settings** -> **General** -> **Login Items**.
6. **Expected Outcome**: "Overtype" is listed under "Open at Login".
7. (Optional) Log out and log back into your Mac account.
8. **Expected Outcome**: Overtype launches automatically and appears in the menu bar.

## Scenario 3: Disable Launch at Login

1. Click the Overtype menu bar icon.
2. Select **Settings**.
3. Uncheck the **Launch at Login** box.
4. Open macOS **System Settings** -> **General** -> **Login Items**.
5. **Expected Outcome**: "Overtype" is removed from the "Open at Login" list.
6. (Optional) Log out and log back into your Mac account.
7. **Expected Outcome**: Overtype does *not* launch automatically.

## Scenario 4: Error Handling Simulation (Optional)

1. It is difficult to artificially induce an `SMAppService` error in a healthy OS environment, but you can verify the error UI code logic by temporarily hardcoding an error throw in `LaunchAtLoginManager`'s setter during development.
2. **Expected Outcome**: Toggling the checkbox shows a human-readable error message in the Settings UI and the checkbox reverts to its actual system state.
