# Contract: Version row on the Settings General tab

**Feature**: `006-settings-version-display` | **Surface**: user interface

This is the contract between the version value and the user. It is what the
manual acceptance procedure checks.

## Location

- Window: Settings, General tab.
- Position: the last group in the tab, after the "Save Preferences" group.
- Visible without opening a disclosure, pressing a button, or hovering.

## Rendering

| Element | Required content |
|---------|------------------|
| Label | The exact text `Version` |
| Value | `AppVersion.displayString` (see [data-model.md](../data-model.md)) |

Value states, restated here so the acceptance run can be performed without
reading the data model:

| Bundle state | Value shown |
|--------------|-------------|
| Version and build both readable | `1.2.1 (20)` (numbers vary by build) |
| Version readable, build missing or blank | `1.2.1` |
| Version missing or blank | `Unknown` |

## Behavioural guarantees

The implementation MUST satisfy all of the following:

1. **Read-only.** The value cannot be focused for editing, typed into, or changed
   by any interaction.
2. **Not part of saving.** Pressing "Save Preferences" does not read, write or
   validate the version, and the version row never causes the tab to be considered
   modified.
3. **Selectable.** The value can be selected with the pointer and copied with the
   standard system command. The application itself performs no pasteboard access;
   the copy is entirely a system action on explicit user command.
4. **Stable within a session.** Reopening the Settings window shows the same value.
5. **Silent.** Rendering the row performs no network request of any kind: no
   update check, no release-notes lookup, no telemetry.
6. **Non-destructive to layout.** The existing General tab controls (launch at
   login, speed multiplier, HUD toggle, chunk size, delay, per-application
   overrides, Save) keep their positions and behaviour. A long version string
   wraps or truncates within the window rather than widening it or clipping other
   controls.
7. **Appearance-aware.** The row follows the system light and dark appearance and
   the system text size, like every other row in the window.

## Explicit non-goals

The row MUST NOT include any of the following, all of which are out of scope by
the specification:

- An "check for updates" or "you are up to date" indication.
- A link to release notes, a changelog, or the repository.
- A copy button (selection is sufficient).
- Versions of providers, dependencies, or macOS.
- A visual marker distinguishing a local build from a release.
