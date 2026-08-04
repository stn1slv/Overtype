# Feature Specification: Application Version in Settings General Tab

**Feature Branch**: `006-settings-version-display`

**Created**: 2026-08-04

**Status**: Draft

**Input**: User description: "I would like to print the version of the application in Settings...-> General tab"

## Clarifications

### Session 2026-08-04

- Q: Should this feature also make the application's declared version stay in sync with the release tag automatically, or is a one-time manual correction enough? → A: The build stamps the version into the application bundle at build time. A tagged release uses the release tag; a local build falls back to the value already declared in the project. The displayed version can therefore never disagree with the release it came from.
- Q: How should the version and build be shown on the General tab? → A: One line following the macOS convention: the label "Version" with the value `1.2.1 (20)`, where the number in parentheses is the build identifier.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find out which version is installed (Priority: P1)

A user has Overtype running in the menu bar and wants to know which version of the
application they are currently using, for example before deciding whether to
update, or when checking whether a fix they read about is already installed.
They open the settings window, look at the General tab, and read the version
there without leaving the application.

**Why this priority**: This is the entire point of the request. Today there is no
place inside the application that states its version, so a user has to inspect the
installed application bundle in Finder or use the command line. Delivering only
this story already solves the problem completely.

**Independent Test**: Open Settings, select the General tab, and confirm a version
value is displayed and matches the version of the installed application.

**Acceptance Scenarios**:

1. **Given** the application is installed and running, **When** the user opens
   Settings and views the General tab, **Then** the application version is shown
   as readable text without any further interaction (no button press, no expanding
   of a section, no scrolling past the point where other General settings end).
2. **Given** the General tab is open, **When** the user reads the version area,
   **Then** it is clearly labelled as the application version and cannot be
   confused with the other numeric settings on the tab (typing speed, chunk size,
   delay).
3. **Given** the user changes and saves other preferences on the General tab,
   **When** the save completes, **Then** the displayed version is unchanged and no
   part of the version display can be edited or saved.

---

### User Story 2 - Report the version when asking for help (Priority: P2)

A user hits a problem and wants to file an issue or ask for help. They need to
state exactly which version they are running, including the build, so the
maintainer can reproduce the problem against the right code. They copy the version
text out of the General tab and paste it into the issue.

**Why this priority**: Useful and cheap, but the primary need (knowing the version)
is already met by Story 1. Copying can be worked around by typing the number by
hand.

**Independent Test**: Open the General tab, select the version text with the
pointer, copy it, and paste it into a text editor; the pasted text matches what
was displayed.

**Acceptance Scenarios**:

1. **Given** the General tab is open, **When** the user selects the version text
   and copies it, **Then** the copied text contains the released version and the
   build identifier in the form `1.2.1 (20)`.
2. **Given** the user has copied the version text, **When** they paste it
   elsewhere, **Then** the pasted value is unambiguous enough to identify one
   specific released build.

---

### User Story 3 - Version stays correct after an update (Priority: P3)

A user updates Overtype to a newer release. When they next open the General tab,
the version shown is the new one, without anyone having had to remember to edit
either the settings screen or the project's declared version as part of the
release.

**Why this priority**: This protects the value of Stories 1 and 2 over time. A
version display that silently goes stale is worse than none, because it actively
misleads. It is P3 only because it is not observable on the first release.

**Independent Test**: Display the version, install a build whose declared version
differs, reopen the General tab, and confirm the newly displayed value matches the
new build.

**Acceptance Scenarios**:

1. **Given** two builds of the application that declare different versions,
   **When** each is launched and its General tab opened, **Then** each shows its
   own declared version.
2. **Given** a release is published from a version tag, **When** the user installs
   that release and opens the General tab, **Then** the version shown matches the
   released version exactly, with no manual edit having been required anywhere in
   the project to make that true.
3. **Given** a developer builds the application locally, outside any release,
   **When** they open the General tab, **Then** a version is still shown, taken
   from the version the project declares by default.

---

### Edge Cases

- **Version metadata missing or unreadable** (for example the application is
  started in a way that does not provide bundle metadata, such as running the raw
  executable during development): the General tab MUST still open and remain fully
  usable, and the version row MUST show the placeholder "Unknown" rather than an
  empty space, a zero, or a crash.
- **Unusual version strings** (pre-release suffixes such as `1.2.0-beta.1`, long
  build identifiers): the version text MUST remain readable within the settings
  window and MUST NOT push other General tab controls out of view or clip the
  value.
- **Local build outside a release**: the displayed version is the one the project
  declares by default, which may repeat a previously released version. This is
  accepted; distinguishing local builds from releases is not a goal of this
  feature.
- **Settings window reopened during the same session**: the version shown is the
  same each time; it does not depend on when the window was opened.
- **Accessibility and appearance**: the version text respects the system light and
  dark appearance and the system text size, like the rest of the settings window.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The General tab of the settings window MUST display the version of
  the running application.
- **FR-002**: The displayed version MUST be derived from the application's own
  declared release metadata, not from a value duplicated inside the settings
  screen.
- **FR-002a**: The version an application build declares about itself MUST be set
  when that build is produced. A build produced for a published release MUST
  declare the released version. A build produced outside a release MUST declare
  the version the project declares by default, so a version is always available.
- **FR-002b**: Publishing a release MUST NOT require any person to edit a declared
  version by hand in order for the released application to report the correct
  version.
- **FR-003**: The version display MUST show, on a single line, the label "Version"
  and a value in the macOS convention `<released version> (<build identifier>)`,
  for example `1.2.1 (20)`.
- **FR-004**: The version MUST be presented as read-only information. It MUST NOT
  be editable, and it MUST NOT participate in the tab's save action or mark the
  settings as changed.
- **FR-005**: The version text MUST be selectable so the user can copy it.
- **FR-006**: The version row MUST carry the label "Version", laid out
  consistently with the other labelled rows of the General tab, so it is
  distinguishable from the configurable numeric fields on the same tab.
- **FR-007**: When the application's version metadata cannot be read, the row MUST
  still appear with its label, and the rest of the General tab MUST continue to
  work normally. The value shown depends on which part is unreadable:
  - The released version cannot be read: the row MUST show the explicit
    placeholder "Unknown", whether or not a build identifier is available. A bare
    build identifier names nothing a user can match against a release.
  - The released version can be read but the build identifier cannot: the row MUST
    show the released version on its own. A usable answer is not discarded over a
    missing secondary identifier, and no empty pair of parentheses is ever
    rendered.
- **FR-008**: Displaying the version MUST NOT trigger any network activity. In
  particular, no update check, no "new version available" lookup, and no
  telemetry, in line with the project's privacy constraint.
- **FR-009**: The version display MUST NOT introduce any new persisted data; it is
  read at display time and nothing about it is written to the configuration file
  or to any other store.
- **FR-010**: The feature MUST NOT change any existing General tab behaviour:
  launch at login, typing cadence settings, per-application overrides, and saving
  preferences MUST behave exactly as before.

### Key Entities

- **Application version information**: the released version identifier and the
  build identifier that the running application declares about itself. It is
  read-only for this feature, has a single source in the project, and has no
  relationship to the user's configuration data.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user who wants to know which version they are running can find it
  in under 10 seconds from opening the settings window, with no more than two
  interactions (open Settings, select General).
- **SC-002**: A user can identify their exact installed build without leaving the
  application and without using Finder, the command line, or any external tool.
- **SC-003**: The value shown matches the version of the installed application in
  100% of checked builds, including immediately after an update.
- **SC-004**: Opening the General tab performs zero outbound network requests.
- **SC-005**: When version information is unavailable, 100% of such cases show a
  clear placeholder and zero cases show a blank, a misleading number, or a
  failure to open the tab.
- **SC-006**: All existing General tab settings continue to load, change, and save
  correctly, verified by the existing manual acceptance procedure.
- **SC-007**: For an application built from a published version tag, the version
  shown equals that tag's version in 100% of releases, and the release requires
  zero manual version edits to achieve this.

## Assumptions

- The version shown is the version of the running application, and there is no
  requirement to display the versions of individual components, providers, or
  dependencies.
- The version declared by the running application is the single source of truth
  for what the settings screen shows. Keeping that declared value in agreement
  with the published release is part of this feature (see FR-002a and FR-002b),
  and the version currently declared by the project disagrees with the most recent
  release, so it is corrected as part of this work.
- The project's release process is already driven by a version tag, and that tag
  is the authority for what a released build declares.
- The version is displayed in the General tab only. No separate "About" window, no
  menu bar "About Overtype" item, and no change to any other tab is in scope.
- No update checking, release notes, changelog link, or "you are up to date"
  indication is in scope. The project's privacy principle forbids update pings.
- The version area is placed at the end of the General tab, after the existing
  settings, so it does not displace the controls users interact with most.
- The user interface language remains English only.
- Beyond reading and displaying the version, the only other area this feature
  touches is how a build declares its own version. It does not affect the text
  transformation pipeline, the Accessibility integration, or any provider.
