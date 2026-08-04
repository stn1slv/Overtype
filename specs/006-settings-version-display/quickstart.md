# Quickstart & Manual Acceptance: Application Version in Settings General Tab

**Feature**: `006-settings-version-display` | **Date**: 2026-08-04

Automated coverage is limited to the pure formatting rules, per Constitution
Principle VIII. Everything else in this feature (bundle metadata, the SwiftUI row,
the stamping step) is system-boundary work and is verified by the procedure below.
Record the outcome in `docs/compatibility.md` before release.

## Prerequisites

- macOS 13 or later, Xcode command line tools installed.
- The repository checked out with git history available (the commit count is read
  from it).
- Accessibility permission is **not** required for this feature. Note that
  rebuilding changes the ad-hoc signature, so the permission for the rest of the
  application must be re-granted in System Settings > Privacy & Security >
  Accessibility after any run of `build-app.sh`.

## 1. Unit tests (automated)

```bash
make test
# or, to run only this feature's tests:
swift test --filter AppVersionTests
```

If this fails with `no such module 'XCTest'`, the active developer directory is
the Command Line Tools rather than Xcode. Either prefix the command with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or switch permanently
with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. The
release workflow already does the equivalent.

**Expected**: the whole suite passes, including the new `AppVersionTests` cases
listed in [research.md](./research.md) D7 (both values, missing build, missing
version, both missing, whitespace-only values, whitespace trimming, pre-release
version string passed through unchanged).

Run this once before making changes to confirm a green baseline, and again after.

## 2. Stamping: released build

```bash
OVERTYPE_VERSION=1.2.1 ./scripts/build-app.sh
defaults read "$PWD/Overtype.app/Contents/Info.plist" CFBundleShortVersionString
defaults read "$PWD/Overtype.app/Contents/Info.plist" CFBundleVersion
```

**Expected**:

- `CFBundleShortVersionString` prints `1.2.1`.
- `CFBundleVersion` prints the current commit count (`git rev-list --count HEAD`,
  20 at the time of writing).

## 3. Stamping: signature and repository invariants

```bash
codesign --verify --deep --strict "$PWD/Overtype.app" && echo "signature OK"
git status --porcelain Sources/Overtype/Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PWD/Overtype.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$PWD/Overtype.app/Contents/Info.plist"
```

**Expected**:

- `signature OK` is printed, proving the stamping happened before signing
  (invariant 1 of the stamping contract).
- `git status --porcelain` prints nothing: the tracked `Info.plist` was not
  modified by the build (invariant 2).
- `CFBundleIdentifier` prints `com.github.stn1slv.Overtype` and `LSUIElement`
  prints `true`, proving unrelated keys survived (invariant 3).

## 4. Stamping: unstamped local build

```bash
./scripts/build-app.sh   # no OVERTYPE_VERSION, HEAD not on a tag
defaults read "$PWD/Overtype.app/Contents/Info.plist" CFBundleShortVersionString
```

**Expected**: the version falls back to the value checked into `Info.plist`
(`1.2.1`) and the build identifier is still the commit count. If `HEAD` happens to
sit on a tag, the tag version is used instead; that is correct behaviour, not a
failure.

## 5. Display: the General tab row

1. Open `Overtype.app` (double-click the bundle; running the raw executable is not
   a faithful launch).
2. Open Settings from the menu bar icon and select the **General** tab.
3. Scroll to the bottom of the tab.

**Expected**:

- A row labelled `Version` is visible after the "Save Preferences" group.
- Its value matches what step 2 printed, in the form `1.2.1 (20)`.
- The value cannot be clicked into and edited.
- Selecting the text and pressing the standard copy command, then pasting into any
  text editor, yields exactly the displayed string.
- Pressing "Save Preferences" shows the usual "Saved!" confirmation and leaves the
  version unchanged.
- **Reopen stability**: close the Settings window, reopen it, and select the
  General tab again. The version value is identical to what was shown before
  (contract guarantee 4).
- **Findability (SC-001)**: from opening the Settings window, the version is found
  in under 10 seconds using at most two interactions (open Settings, select
  General). Configure at least three per-application overrides first, so the check
  is made against a tab long enough to scroll.

## 6. Display: existing behaviour unaffected (FR-010, SC-006)

On the same General tab, confirm each still works as before:

- Toggle "Launch at login" off and on; the state persists across reopening the
  window.
- Move the speed multiplier slider; the numeric readout follows it.
- Toggle "Show HUD".
- Enter and clear a default chunk size and a default delay.
- Add a per-application override, save, reopen Settings, and confirm it persisted.

**Expected**: no regression in any of the above.

## 7. Display: appearance and long values

1. Switch the system appearance between Light and Dark (System Settings >
   Appearance) with the Settings window open.
2. Change the system text size once (System Settings > Appearance > Text size, or
   the accessibility text size control) and reopen the tab.
3. Optionally rebuild with `OVERTYPE_VERSION=1.3.0-beta.1` and reopen the tab.

**Expected**: the row is legible in both appearances, the label and value follow
the system text size like the rest of the window (contract guarantee 7), and the
longer pre-release string is shown in full without widening the window or clipping
other controls.

## 8. Display: unknown value path

This path is exercised by the unit tests. To confirm it visually, temporarily
remove the version key from a built bundle:

```bash
/usr/libexec/PlistBuddy -c "Delete :CFBundleShortVersionString" "$PWD/Overtype.app/Contents/Info.plist"
codesign --force --deep --sign - -i com.github.stn1slv.Overtype "$PWD/Overtype.app"
open "$PWD/Overtype.app"
```

**Expected**: the General tab still opens and works normally, and the version row
reads `Version  Unknown`. Rebuild afterwards with `./scripts/build-app.sh` to
restore a correct bundle.

## 9. Privacy check (FR-008, SC-004)

With the Settings window open on the General tab, confirm no network activity
originates from Overtype, for example using Activity Monitor's Network tab or
`nettop -p $(pgrep -x Overtype)`.

**Expected**: zero outbound connections while the tab is displayed.

## Recording the result

Add a dated line to `docs/compatibility.md` stating which build was tested, the
version string shown, and that steps 2 through 9 passed. A release must not ship
if any step regresses against the previously recorded result.
