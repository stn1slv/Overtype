# Feature Specification: Overtype (Reword)

**Feature Branch**: `[###-feature-name]`

**Created**: 2026-07-31

**Status**: Draft

**Input**: User description: "/speckit-specify /Users/Stanislav_Deviatov/Downloads/BUILD_SPEC.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Apply Grammar Correction in Chat Applications (Priority: P1)

A user selects text they typed in a messaging application and presses a global keyboard shortcut to fix their grammar.

**Why this priority**: Validates the core text reading and writing capabilities in a complex third-party application.

**Independent Test**: Can be fully tested by selecting text in a chat app, pressing the shortcut, and verifying the text changes and the user's clipboard is untouched.

**Acceptance Scenarios**:

1. **Given** text selected in a chat application, **When** the "Fix grammar" shortcut is pressed, **Then** the text is read by the system, sent to the AI service, and the response is typed back replacing the selection, leaving the clipboard unchanged.

---

### User Story 2 - Adjust Tone to Formal (Priority: P2)

A user wants to quickly rewrite a selected casual message into a formal tone using a different configured shortcut.

**Why this priority**: Ensures the system can handle multiple user-defined actions and route to the correct prompt template and AI parameters.

**Independent Test**: Add the new action via configuration, press the new shortcut, and ensure the text is rewritten formally.

**Acceptance Scenarios**:

1. **Given** a casual email draft, **When** the "Make formal" shortcut is pressed, **Then** the text is rewritten in a business register without breaking formatting.

---

### User Story 3 - Use Local AI Model for Privacy (Priority: P3)

A privacy-conscious user configures an action to run entirely on a local AI model to ensure data never leaves their machine.

**Why this priority**: Validates the extensibility of the AI providers and compliance with strict privacy expectations.

**Independent Test**: Run a local model service, select text, and trigger the action; verify the text is transformed instantly without external network requests.

**Acceptance Scenarios**:

1. **Given** a local AI service running, **When** a local action is triggered, **Then** text is processed successfully without leaving the machine.

### Edge Cases

- What happens when the target application loses focus while the AI request is in flight? The write is aborted to avoid replacing text in the wrong window.
- How does the system handle selecting text in an unsupported application (e.g., terminal emulator)? The application detects it is unsupported and shows a clear error message instead of failing silently.
- What if the user is physically holding modifier keys when the replacement starts? The app waits for the physical release of modifier keys before typing the replacement.
- What if the AI wraps the output in quotation marks? The response sanitizer automatically strips them if the original text had none.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST read the user's selected text without touching the operating system clipboard.
- **FR-002**: System MUST replace the selected text in place securely and reliably.
- **FR-003**: System MUST provide a mechanism for users to add new text transformation actions via configuration, without any code changes.
- **FR-004**: System MUST support multiple AI backends (both cloud-based and local).
- **FR-005**: System MUST run as a background menu bar utility without a dock icon or main window.
- **FR-006**: System MUST securely store all authentication keys and secrets natively.
- **FR-007**: System MUST provide visual feedback (HUD panel) for ongoing tasks that does not steal keyboard focus.
- **FR-008**: System MUST sanitize AI responses to strip markdown and unnecessary quotes when appropriate.
- **FR-009**: System MUST allow users to cancel in-flight AI requests seamlessly (e.g., by pressing Escape).
- **FR-010**: System MUST NOT silently fail; all errors must be presented to the user clearly.

### Key Entities

- **Action Configuration**: Defines an automation (e.g., prompt, shortcut, provider, behavior).
- **Provider Configuration**: Defines an AI backend (e.g., URL, model, timeout).
- **Global Settings**: Defines application settings (e.g., typing speed, HUD visibility).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The user's system clipboard is verifiably unchanged after executing any action.
- **SC-002**: Text replacement completes smoothly and reliably across native and web-based desktop applications.
- **SC-003**: Users can add new AI providers and custom actions dynamically via configuration without restarting the application.
- **SC-004**: No user text, AI output, or secrets are logged persistently unless explicitly opted-in by the user for diagnostics.
- **SC-005**: The application handles failures gracefully, leaving the original selected text fully intact upon any error.

## Assumptions

- Terminal emulators are explicitly out of scope for the initial version.
- Streaming AI responses and partial text replacements are out of scope.
- The original selected text survives completely if any network or API error occurs.
