# Feature Specification: Launch at Login

**Feature Branch**: `[002-launch-at-login]`

**Created**: 2026-08-01

**Status**: Completed

**Input**: User description: "I would like to add configuration option 'launch at login' as a checkbox. Also, don't forget to increment minor version of the application"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Launch at Login (Priority: P1)

Users should be able to configure Overtype to automatically launch when they log into their Mac, so that the utility is always available without manual intervention.

**Why this priority**: Core expectation for a system-level utility application like Overtype.

**Independent Test**: Can be fully tested by enabling the option in the UI, restarting the Mac (or logging out and back in), and verifying that Overtype runs automatically.

**Acceptance Scenarios**:

1. **Given** Overtype is running and not configured to launch at login, **When** the user checks the "Launch at Login" box in settings, **Then** the application is registered as a login item in macOS.
2. **Given** Overtype is registered as a login item, **When** the user logs out and logs back in, **Then** Overtype launches automatically.

---

### User Story 2 - Disable Launch at Login (Priority: P1)

Users should be able to stop Overtype from launching automatically if they prefer to start it manually.

**Why this priority**: Users must remain in control of what runs on their machine automatically.

**Independent Test**: Can be fully tested by disabling the option, logging out and back in, and ensuring Overtype does not start.

**Acceptance Scenarios**:

1. **Given** Overtype is configured to launch at login, **When** the user unchecks the "Launch at Login" box in settings, **Then** the application is deregistered as a login item in macOS.
2. **Given** Overtype is deregistered as a login item, **When** the user logs out and logs back in, **Then** Overtype does not launch automatically.

---

### Edge Cases

- What happens if the user removes Overtype from login items via macOS System Settings rather than the application UI? The application UI should accurately reflect the system state when opened.
- What happens if the application is moved to a different directory? (Native APIs usually handle this gracefully).
- How is failure handled if registering as a login item fails due to system permissions or other errors?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a checkbox labeled "Launch at Login" in the application's configuration/settings UI.
- **FR-002**: The system MUST register or deregister the application as a macOS login item synchronously when the checkbox state is changed.
- **FR-003**: The UI checkbox state MUST reflect the actual OS-level login item state when the settings interface is opened.
- **FR-004**: The system MUST increment the application's minor version (e.g., from v1.X.x to v1.(X+1).0) in the relevant project configuration.
- **FR-005**: If registration/deregistration fails, the system MUST notify the user via a human-readable error (following Constitution Principle VI: No Silent Failure) and revert the UI checkbox to match the true system state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can successfully enable the setting and verify the app starts automatically on a subsequent login.
- **SC-002**: Users can successfully disable the setting and verify the app no longer starts automatically on login.
- **SC-003**: 100% of the time, the application's Settings UI correctly reflects the system's actual login item state.
- **SC-004**: The application version is visibly incremented in the build output / application bundle.

## Assumptions

- The implementation will use modern macOS APIs (e.g., `SMAppService.mainApp` introduced in macOS 13 Ventura), aligning with Overtype's deployment target of macOS 13+.
- Modifying the minor version implies a feature update release, which aligns with adding this new user-facing functionality.
