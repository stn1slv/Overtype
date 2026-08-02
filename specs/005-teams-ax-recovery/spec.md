# Feature Specification: Reliable Selection Reading for Apps with Dormant Accessibility Trees

**Feature Branch**: `005-teams-ax-recovery`

**Created**: 2026-08-02

**Status**: Draft

**Input**: User description: "Reliable focused-element lookup for apps with dormant accessibility trees (Microsoft Teams). After the Teams process restarts, all accessibility queries return no value instantly, so Overtype's single-shot focused-element lookup fails with noFocusedElement in ~12 ms. Empirically confirmed on 2026-08-02: setting the assistive-client flags on the target app wakes the tree (the call reports an error yet takes effect). Fix: when the existing lookup strategies find nothing, escalate once per run: set the wake-up flags ignoring reported error codes, apply a messaging timeout, and retry the app-element-first lookup up to 12 attempts at 150 ms intervals (the empirically validated configuration from the 2026-07-31 axprobe findings). The fast path for well-behaved apps must remain untouched. Escalation must respect cancellation and the hard timeout. Manual acceptance: restart Teams, confirm recovery; record in docs/compatibility.md."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fix text in Teams after Teams has restarted (Priority: P1)

A user restarts Microsoft Teams (or Teams updates itself, or the Mac reboots). Later, they select a sentence in the Teams compose box and press their Overtype shortcut. Today this fails instantly with "Cannot find the focused text element" and keeps failing until an external assistive tool touches Teams. After this feature, the run succeeds: Overtype detects that the app's accessibility information is not available yet, wakes it, retries briefly, and completes the transformation.

**Why this priority**: This is the reported regression. Teams is a primary target application, and the failure mode returns after every Teams restart, making Overtype appear randomly broken.

**Independent Test**: Quit and relaunch Microsoft Teams, select text in the compose box, invoke the action. Delivers value if the run completes without any manual warm-up step.

**Acceptance Scenarios**:

1. **Given** Teams was freshly restarted and no assistive tool has touched it, **When** the user selects text in Teams and invokes an action, **Then** the selection is read and replaced successfully within the normal run flow, at most a few seconds slower than a warm run.
2. **Given** Teams has already served one successful run since its restart, **When** the user invokes an action again, **Then** the run is as fast as before this feature (no added delay).

---

### User Story 2 - No regression for well-behaved apps (Priority: P2)

A user invokes an action in an application whose accessibility support works immediately (native apps, Outlook, warmed-up Teams). Nothing about their experience changes: same latency, no extra prodding of the target application.

**Why this priority**: The recovery path must not tax the common case. Some applications are known to misbehave when assistive-client flags are set (window-resize glitches in certain cross-platform apps), so the flags must not be set when not needed.

**Independent Test**: Run the action in Outlook and a native app before and after the change; observed latency and behavior are unchanged.

**Acceptance Scenarios**:

1. **Given** an app whose focused element is found by the existing lookup, **When** an action runs, **Then** no wake-up flags are set on that app and no retry delay is added.

---

### User Story 3 - Failures still fail fast and clearly (Priority: P3)

A user invokes an action with no text selected, or in a genuinely unsupported application (for example a terminal emulator). The run must still end with the same specific, human-readable error as today, after the bounded retry window, and pressing Escape during the retry window must cancel immediately.

**Why this priority**: The retry window must not turn hard failures into long hangs or break cancellation guarantees.

**Acceptance Scenarios**:

1. **Given** no text is selected anywhere, **When** an action is invoked, **Then** the user sees the same specific error as today, and the total added wait does not exceed the bounded retry window (about two seconds).
2. **Given** the retry window is in progress, **When** the user presses Escape, **Then** the run cancels promptly and nothing is modified.

---

### Edge Cases

- Target app quits or loses frontmost status during the retry window: the run must abort without writing (existing context re-check still applies).
- The wake-up call reports an error even when it works: the reported error code must not be treated as failure evidence (verified quirk).
- An app that never exposes a selection (terminal emulators): the retry window ends in the existing specific error; the app is not retried indefinitely.
- Repeated invocations while a retry window is active: the existing cancel-previous-run behavior applies unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When the existing focused-element lookup strategies find no element with a live selection, the system MUST attempt a bounded recovery instead of failing immediately.
- **FR-002**: The recovery MUST wake the target application's accessibility support by setting the two known assistive-client flags on the target application, and MUST ignore the reported result codes of those calls, because at least one target application (Microsoft Teams) reports an error while honoring the call. This site MUST carry an inline comment naming the quirk (Principle III).
- **FR-003**: The recovery MUST retry the focused-element lookup, querying the application element first, up to 24 attempts at 150 ms intervals. The ordering and interval come from the 2026-07-31 axprobe findings (binding conclusion #3); the attempt count was raised from the findings' 12 after the 2026-08-02 acceptance run showed a truly cold Teams populates the selection attribute only about 2.7 seconds after the wake.
- **FR-004**: The recovery MUST apply a bounded messaging timeout (2 seconds) to accessibility queries issued during the recovery, so a hung target application cannot stall a run beyond the hard timeout.
- **FR-005**: The fast path MUST remain unchanged: if the existing strategies find the selection, no flags are set, no retries occur, and no latency is added.
- **FR-006**: The recovery window MUST respect cancellation: a user-initiated cancel (Escape) during the retry window MUST end the run promptly with no modification to the target document.
- **FR-007**: If recovery does not find a selection within the bounded window, the run MUST end with the same specific, typed errors as today (no new silent failure modes, no indefinite waiting).
- **FR-008**: The empirical basis and the per-application outcome MUST be recorded in `docs/compatibility.md` (Teams dormant-tree behavior, the wake-up quirk, and the re-verified acceptance results).

### Key Entities

- **Recovery attempt**: a bounded sequence (wake flags once, then up to 12 lookup retries at 150 ms) executed at most once per run.
- **Wake-up flags**: the two assistive-client attributes that signal "an assistive client is present" to the target application; one is honored by Teams-like apps (despite the reported error), the other by Electron apps.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After restarting Microsoft Teams, the first Overtype run against a Teams selection succeeds without any external warm-up, in at most 3 seconds more than a warm run.
- **SC-002**: Runs against applications that already work (Outlook, native apps, warmed Teams) show no measurable latency increase (within normal variance) and no behavioral change.
- **SC-003**: With nothing selected, the failure message is unchanged; in apps with an awake tree it stays instant, and in the cold-tree case the added delay stays within the bounded recovery window (about four seconds).
- **SC-004**: Escape pressed during the recovery window cancels the run in under one second, with the target document untouched.
- **SC-005**: The recorded manual acceptance for Teams in `docs/compatibility.md` passes from a cold Teams restart, twice in a row.

## Assumptions

- The 2026-08-02 diagnosis is correct and reproducible: Teams' accessibility tree is dormant after process restart, and setting the assistive-client flag wakes it even though the call reports an error. The manual acceptance procedure will re-verify this from a cold restart before merge.
- The 12 x 150 ms retry configuration from the 2026-07-31 axprobe findings is sufficient for Teams and VS Code class applications; no per-app tuning is needed in this feature.
- Setting the wake-up flags only on the failure path is an acceptable trade-off for avoiding known side effects (window-resize glitches in some Electron apps) on apps that do not need them.
- No configuration surface is added: the recovery is automatic and invisible; constants live in code, matching the tested values.
- Writing (typing) behavior is out of scope; this feature only changes how the selection is found and read.
