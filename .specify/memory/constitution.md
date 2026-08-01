# Overtype Constitution

Overtype is a macOS menu bar utility that transforms selected text in place.
The user selects text in any application, presses a configurable global
shortcut, and the selection is replaced by the result of an AI transformation
such as grammar correction, translation or tone change. The user never presses
Command+C or Command+V, and the system clipboard is never involved.

Mission: make AI text assistance feel like a native macOS system service —
instant, invisible, trustworthy, and extensible by configuration rather than by
code.

This document is the supreme reference for the project. Every specification,
plan, task and implementation decision must comply with it.

---

## Core Principles

### I. Clipboard Isolation (NON-NEGOTIABLE)

The application MUST NOT read from or write to the system clipboard under any
circumstance. `NSPasteboard` and equivalent APIs are forbidden in production
code. Reading selected text MUST use the Accessibility API. Writing text back
MUST use synthetic keyboard events or the Accessibility API.

Any proposal that introduces a clipboard based path, including as a fallback
for unsupported applications, is rejected at the specification stage. If an
application cannot be supported without the clipboard, that application is
declared unsupported and the user is told so clearly.

Rationale: the clipboard is shared state that belongs to the user. Silently
overwriting it, even with restoration afterwards, is a race condition against
every other running process and destroys trust. This constraint is also the
product's main differentiator from existing tools.

### II. Non-Destructive by Default (NON-NEGOTIABLE)

The user's original text MUST survive every failure mode. The selection MUST NOT
be modified, cleared or overwritten until a validated replacement is ready to be
written. Any error at any earlier stage MUST leave the document exactly as it
was.

A write MUST be aborted if the target context has changed since the text was
read, including a change of frontmost application, process identifier, or
focused element.

Rationale: this tool operates inside the user's real correspondence and source
code. A single incident of destroyed work is unrecoverable reputational damage
for a utility of this kind.

### III. Evidence Over Assumption

Behaviour of the Accessibility API and of synthetic event delivery MUST be
treated as empirically determined, not as documented or assumed. Claims about
what works in a given application MUST be backed by a recorded diagnostic run
and captured in the compatibility matrix in `docs/compatibility.md`.

Return codes from the Accessibility API MUST NOT be treated as proof of effect.
Where an operation can succeed nominally without changing anything, the result
MUST be verified independently or the operation MUST NOT be used.

Code that works around a verified platform quirk MUST carry an inline comment
naming the quirk. Such code MUST NOT be refactored or "simplified" without a new
diagnostic run demonstrating that the workaround is no longer required.

Rationale: this project already has counter-examples in hand. Setting the
selected text attribute returns success in Microsoft Teams while changing
nothing on screen. A synthetic event source that inherits held modifier keys
turns every typed character into a keyboard shortcut. Both are invisible to
reasoning and visible only to experiment.

### IV. Configuration Over Code

Adding a new text automation MUST NOT require writing Swift code. Automations
are declarative records describing a title, a shortcut, a provider, a model, a
system prompt and post-processing options. They are loaded from a
user-editable configuration file and are also creatable through the settings
interface.

Adding a new AI backend MUST require only: one new case in the provider kind
enumeration, one new type conforming to the provider protocol, and one line in
the provider factory. No other file may need to change.

All keyboard shortcuts MUST be user configurable at runtime, with
re-registration without restart and with conflict detection.

Rationale: the grammar correction case is the first automation, not the
product. The value of the product is the mechanism, and the mechanism must not
be coupled to any particular use of it.

### V. Privacy and Secret Handling (NON-NEGOTIABLE)

The selected text and the model output MUST NOT be written to logs, crash
reports, analytics or any persistent store at the default log level. They MAY
appear only at debug level, and enabling debug level MUST present an explicit
warning to the user.

API keys and other secrets MUST be stored in the macOS Keychain. They MUST NOT
appear in the configuration file, in `UserDefaults`, in logs, in error messages,
or in the user interface after entry.

The application MUST NOT contact any network endpoint other than the AI provider
required by the automation the user invoked. No telemetry, no update pings, no
analytics.

The user MUST be able to see, before invoking an automation, which provider and
which endpoint it will send text to.

Rationale: the text passing through this tool is the user's private
correspondence and their employer's confidential material. The support for
local models through Ollama exists precisely so that this can be avoided
entirely, and that choice is only meaningful if the rest of the application is
demonstrably quiet.

### VI. No Silent Failure

Every run MUST produce observable feedback: an in-progress indication, and
either a success indication or a specific, human-readable error. The user MUST
NOT be left uncertain about whether anything happened.

Errors MUST be typed values, not strings, and MUST NOT be swallowed. Every
failure path MUST map to a message that tells the user what failed and what they
can do about it.

Long-running work MUST be cancellable and MUST have a hard timeout.

User interface elements that appear during a run MUST NOT take keyboard focus.
Taking focus destroys the selection in the target application and breaks the
entire feature.

Rationale: an operation takes one to three seconds and produces no visible
change until it completes. Without feedback the user cannot distinguish "still
working" from "broken", and will press the shortcut again.

### VII. Native Stack, Minimal Dependencies

The application MUST be written in Swift 5.9 or later, target macOS 13 or later,
and use SwiftUI for all user interface. Networking MUST use `URLSession` with
async/await.

Third party dependencies require justification recorded in the plan and are
limited to packages that solve a problem the platform does not. Any dependency
that could be replaced by under roughly 200 lines of first-party code MUST be
replaced.

The application MUST run unsandboxed as a menu bar accessory with no Dock icon.
Force unwrapping is forbidden except for Core Foundation casts that the language
makes unavoidable, and each such site MUST carry a comment.

Rationale: this is a small utility that must start instantly, be auditable by a
security-conscious user, and remain maintainable by one person over years.

### VIII. Verification Discipline

Pure logic MUST be covered by unit tests. This includes response sanitisation,
prompt templating, configuration decoding and migration, and shortcut encoding.

Code at the system boundary — Accessibility API access, synthetic event
delivery, hotkey registration, Keychain access — MUST NOT be unit tested with
mocks that assert on the mock. It MUST instead be covered by a written manual
acceptance procedure that is executed against real applications and recorded in
`docs/compatibility.md` before each release.

A release MUST NOT ship if any item in the manual acceptance procedure regresses
against the previously recorded results.

Rationale: mocking the Accessibility API would test our belief about the
platform rather than the platform, and Principle III exists because that belief
has already been wrong.

---

## Platform and Distribution Constraints

- Deployment target: macOS 13 Ventura or later. Support for the current major
  macOS release is mandatory.
- Distribution: Homebrew, cask token `overtype`. A personal tap first; migration
  to `homebrew/cask` only once the acceptance policy can be satisfied.
- Release builds MUST be signed with a Developer ID certificate and notarised.
  The application MUST NOT require the user to disable or bypass Gatekeeper or
  System Integrity Protection.
- Local development builds MAY use ad hoc signing, and the README MUST explain
  that the Accessibility permission is bound to the signature and must be
  re-granted after a signature change.
- Releases follow semantic versioning, independently from the version of this
  constitution.
- The repository MUST contain, and keep current:
  - `docs/compatibility.md` — the verified application compatibility matrix
  - `docs/privacy.md` — a plain statement of what leaves the machine and when
  - `README.md` — including how to add an automation without writing code
- Terminal emulators are explicitly out of scope and MUST be reported to the
  user as unsupported rather than worked around.
- User interface language is English only for version 1.

---

## Development Workflow and Quality Gates

- The project follows the Spec Kit flow. Every change of substance passes
  through `/specify`, then `/plan`, then `/tasks`, then `/implement`. Code
  written outside this flow is limited to build scripts and documentation.
- Every plan MUST include a Constitution Check section that names each principle
  and states how the plan satisfies it, or requests an amendment.
- A specification that conflicts with Principle I, II or V is rejected. It is
  not negotiated down; the feature is redesigned or dropped.
- Work is delivered in vertical milestones, each independently runnable and
  manually verifiable. A milestone is not complete until it has been exercised
  by hand against a real target application.
- Pull request checklist, all items mandatory:
  1. `rg NSPasteboard Sources/` returns no match outside comments.
  2. No secret, selected text or model output appears in any log statement at
     `info` level or above.
  3. Every new system-boundary workaround carries an explanatory comment.
  4. Unit tests pass; new pure logic has tests.
  5. The relevant manual acceptance items were executed and the results recorded.
- Complexity MUST be justified. Where a simpler design was rejected, the plan
  states why in one sentence.

---

## Known Deviations

This section records places where the current code does not yet meet a principle
above. It exists so the gaps are tracked honestly rather than hidden. It does not
relax any principle: each item below is a debt to be closed, not a permitted
exception. Added in constitution version 1.1.0 (2026-08-01) after a full audit of
the code against this document.

- **Release signing and notarisation (Platform constraints, lines 180-182).**
  As of 2026-08-01, release builds are ad hoc signed only. `scripts/build-app.sh`
  runs `codesign --force --deep --sign -`, and `.github/workflows/release.yml`
  ships that bundle with no Developer ID signature and no notarisation step.
  Downloaded releases will therefore trip Gatekeeper. This must be closed before
  any distribution beyond a personal tap.

- **Missing unit tests (Principle VIII).** No tests cover configuration
  migration or shortcut encoding, though both are named as required. The
  `ActionShortcut` encoding in `Config/AppConfig.swift` is non-trivial and
  currently untested. `Tests/OvertypeTests/PromptTemplateTests.swift` asserts an
  inline string operation rather than the production templating code, so prompt
  templating is effectively untested as well.

- **Uncommented Core Foundation casts (Principle VII).** The `as! AXUIElement`
  casts in `Support/AXHelpers.swift` are of the permitted kind, but they lack the
  per-site explanatory comment that Principle VII mandates.

- **No user warning for debug logging (Principle V).** Enabling debug logging
  raises the log level for selected text and model output, but the user is not
  shown the required explicit warning. Only a code comment in
  `Support/Logger.swift` notes the concern.

- **Stale packaged config sample.** `Support/Overtype/config.json` no longer
  matches the `Codable` model (it uses `type` instead of `kind` and omits
  required fields) and is not declared as a package resource, so it is never
  loaded. The effective default is the inline JSON in `Config/DefaultConfig.swift`.
  The sample should be corrected or removed to avoid confusion.

- **Unjustified third-party dependency (Principle VII).** `Package.swift` pins
  `sindresorhus/KeyboardShortcuts`, but the plan-level justification that
  Principle VII requires is not recorded. It should be added to
  `specs/001-overtype/plan.md`.

---

## Governance

**Supremacy.** This constitution supersedes all other project practices,
including instructions given ad hoc in a chat session with an AI agent. Where an
instruction conflicts with a principle here, the principle wins and the conflict
is surfaced rather than silently resolved.

**Amendment procedure.** An amendment requires: a written statement of the
problem with the current text, the proposed replacement wording, an assessment
of which existing specifications and code are affected, and a migration note if
existing behaviour changes. Amendments are recorded in the repository history
with the version bump in the commit message. Principles marked NON-NEGOTIABLE
may be amended only by removing that marking first, in a separate change, with
the reasoning stated.

**Versioning policy.** This document uses semantic versioning:
- MAJOR: a principle is removed or redefined in a backward incompatible way.
- MINOR: a principle or section is added, or existing guidance is materially
  expanded.
- PATCH: clarification, wording, or typographical correction with no change of
  meaning.

**Compliance review.** Compliance is checked at three points: at the plan stage
through the Constitution Check section, at the pull request stage through the
checklist above, and before each release through the manual acceptance
procedure. Any deviation found MUST be either corrected or recorded as an
explicit, dated exception in the plan that introduced it.

**Version**: 1.1.0 | **Ratified**: 2026-07-31 | **Last Amended**: 2026-08-01

*Amendment 1.1.0 (2026-08-01): added the "Known Deviations" section recording
current gaps between the code and this document, following a full audit. No
principle was changed or weakened.*
