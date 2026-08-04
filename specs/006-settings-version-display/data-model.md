# Phase 1 Data Model: Application Version in Settings General Tab

**Feature**: `006-settings-version-display` | **Date**: 2026-08-04

This feature introduces no persisted data, no configuration field and no change to
`AppConfig`. The only new entity is an in-memory, read-only value describing the
running build.

## Entity: `AppVersion`

Represents what the running application declares about itself. Created on demand
when the General tab renders; never stored, never encoded, never sent anywhere.

| Field | Type | Source | Optional | Notes |
|-------|------|--------|----------|-------|
| `shortVersion` | `String?` | `CFBundleShortVersionString` in `Bundle.main.infoDictionary` | Yes | The released, user-facing version, e.g. `1.2.1`. Absent when the executable runs outside an app bundle. |
| `build` | `String?` | `CFBundleVersion` in `Bundle.main.infoDictionary` | Yes | The build identifier, e.g. `20`. Treated as an opaque string, never parsed as a number. |

Derived member:

| Member | Type | Description |
|--------|------|-------------|
| `displayString` | `String` | The text rendered on the General tab, produced by the rules below. Never empty. |

Relationships: none. `AppVersion` has no reference to `AppConfig`, providers,
actions, or any user data, and nothing references it back.

Lifecycle: constructed, read once for display, discarded. No state transitions.

## Normalisation rule

Applied to both fields before any decision is made:

1. Trim leading and trailing whitespace and newlines.
2. A value that is empty after trimming is treated exactly as if it were absent.

This makes a plist entry of `""` or `"  "` behave identically to a missing key, so
there is a single code path for "no usable value".

## Formatting decision table

`shortVersion` and `build` below mean the values *after* normalisation.

| # | `shortVersion` | `build` | `displayString` | Example |
|---|----------------|---------|-----------------|---------|
| 1 | present | present | `<shortVersion> (<build>)` | `1.2.1 (20)` |
| 2 | present | absent | `<shortVersion>` | `1.2.1` |
| 3 | absent | present | `Unknown` | `Unknown` |
| 4 | absent | absent | `Unknown` | `Unknown` |

Row 3 deliberately ignores an orphan build identifier: a bare build number
identifies nothing to a user and cannot be matched against a release.

Version strings are passed through verbatim. A pre-release value such as
`1.3.0-beta.1` produces `1.3.0-beta.1 (21)`; no parsing, validation or
normalisation of the version format is performed.

## Validation rules

- `displayString` MUST NOT be empty in any input state (FR-007, SC-005).
- `displayString` MUST NOT contain an empty pair of parentheses.
- The literal placeholder is exactly `Unknown` (capital U, no punctuation).
- Neither field is ever written, only read (FR-004, FR-009).

## Requirement traceability

| Requirement | Where it is satisfied |
|-------------|----------------------|
| FR-001 | The General tab renders `displayString`. |
| FR-002 | Both fields are read from the running bundle, not from a constant in the view. |
| FR-002a | Build-time stamping sets both keys; see `contracts/build-version-stamping.md`. |
| FR-002b | Version and build are derived from the tag and the commit count, so no manual edit is needed for a release. |
| FR-003 | Decision table row 1. |
| FR-004 | The value is not part of `SettingsViewModel` draft state and is not touched by `saveSettings()`. |
| FR-005 | The rendered value enables text selection. |
| FR-006 | The row is labelled `Version`. |
| FR-007 | Decision table rows 3 and 4, plus the normalisation rule. |
| FR-008 | No field has a network source. |
| FR-009 | The value is computed at display time and never persisted. |
| FR-010 | No existing General tab state is read or modified. |
| SC-003, SC-007 | Guaranteed by the stamping contract rather than by this model. |
