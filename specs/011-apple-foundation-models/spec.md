# Feature Specification: Apple Foundation Models Provider

**Feature Branch**: `011-apple-foundation-models`

**Created**: 2026-11-19

**Status**: Draft

**Input**: User description: "Add an Apple Foundation Models provider. New provider kind (e.g. "apple") that calls Apple's on-device model through the native FoundationModels framework (LanguageModelSession), not the fm CLI and not a subprocess. The package targets macOS 13, so the provider must be gated with #available (FoundationModels is in the macOS 27.2 SDK on this machine) and return a typed, human-readable error when the OS or model is unavailable (check SystemLanguageModel availability: device not eligible, Apple Intelligence not enabled, model not ready). No API key, no baseURL, no network. Map guardrail violations and context-window overflow to typed ProviderError cases. Cancellation (Escape) must stop generation. Follow the three-edit provider rule (ProviderKind case, AIProvider type, ProviderRegistry line) and the model-aware parameters rules (ModelProfiles/GenerationParameterResolver: decide what temperature/reasoning means here). Settings Providers tab must handle a provider with no key and no URL. Context: /usr/bin/fm exists; `fm models` reports system model "AFM 3 Core Advanced" available, pcc unavailable without iCloud; fm's license forbids programmatic access to Apple models except as expressly permitted, which is why the public framework was chosen over the CLI."

## Clarifications

### Session 2026-11-19

- Q: Which macOS versions should the Apple provider support? → A: macOS 27 and later only. macOS 27 replaced the model's error types and deprecated the macOS 26 ones, so supporting 27 only means one error family, less code, and every path testable on the development machine. Supporting macOS 26 as well was rejected because it doubles the error mapping for a version whose path could only be checked by unit tests here. Users on macOS 26 and earlier see the typed "requires macOS 27" error.
- Q: Which safety-filter mode should the Apple provider use? → A: Apple's "permissive content transformations" mode, fixed for every Apple run, with no setting. Overtype only transforms text the user selected, which is the case Apple designed this mode for, and it refuses less ordinary text about sensitive subjects. The default mode was rejected because it produces more false refusals; a per-provider setting was rejected as configuration almost no user would change.
- Q: On macOS 13 to 26, how should the Settings Providers tab treat the Apple kind? → A: Show it, labelled as requiring macOS 27. The user can still save it (for example in a configuration shared with a newer Mac), and a run produces the typed "requires macOS 27" error. Hiding it was rejected because the picker would then disagree with a configuration that already contains an Apple provider.
- Q: Should an explicit creativity (temperature) value ever be withheld for the Apple model? → A: No. The 2026-11-19 diagnostic found no rejected range (0, 1, 2, 5 and -1 all succeeded), so an explicit value is always passed. (Recorded after cross-artifact analysis finding I1.)
- Q: Which model names does the Apple provider accept? → A: An empty name and `system` both mean the on-device system model. Any other name produces the specific "model not available" error naming it, instead of silently falling back. (Recorded after analysis finding I2.)
- Q: What should happen for text in a language the model does not support? → A: The diagnostic showed the model does not reliably report it (Welsh and Amharic input got English answers instead of an error). The typed error is shown when the model does report an unsupported language; otherwise the result is written as for any other answer. The README lists the supported languages and warns that other languages may get English or wrong answers. (Recorded after analysis finding U1.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run an action against Apple's on-device model (Priority: P1)

A user on a Mac with Apple Intelligence enabled configures a provider of the new Apple kind and attaches it to an action such as "Fix grammar". They select text in any supported application, press the action's shortcut, and the selection is replaced by the result from the model built into macOS. No account, no API key, no endpoint address and no separately installed service are involved, and the text never leaves the Mac.

**Why this priority**: This is the whole value of the feature: a zero-setup, private backend that every eligible Mac already has. It is a complete slice on its own.

**Independent Test**: On an eligible Mac with Apple Intelligence on, add one Apple provider and one action that uses it, select text in a known-supported app, trigger the shortcut, and confirm the selection is replaced with the standard Reading / Thinking / Writing feedback.

**Acceptance Scenarios**:

1. **Given** the on-device model is available and an action is bound to an Apple provider, **When** the user selects text and presses the shortcut, **Then** the selection is replaced by the model's transformed text.
2. **Given** an Apple run is in progress, **When** the model is generating, **Then** the user sees the same in-progress feedback as with the existing providers.
3. **Given** an Apple run is in progress, **When** the user presses Escape before the result is written, **Then** generation stops, the run is cancelled, and the selection is unchanged.
4. **Given** the Mac is disconnected from all networks, **When** the user runs an Apple action, **Then** the run completes successfully.

---

### User Story 2 - Add the Apple provider without a key or an address (Priority: P1)

A user adds the Apple provider without code: either by choosing it in the Settings Providers tab, or by declaring a provider record with the Apple kind in the configuration file. Because the model is part of the operating system, the form does not ask for a credential or an endpoint address, and saving without them is the normal case. The form pre-fills the model name with the system model identifier.

**Why this priority**: The product promise is that a new backend is added by configuration. A form that demands a key or an address the Apple kind cannot use would block the feature or invite configurations that look valid but mean nothing.

**Independent Test**: Starting from a default install, add an Apple provider through Settings with no key and no address, attach an action to it, and run it. Separately, add the same provider only by editing the configuration file and confirm it is registered after reload.

**Acceptance Scenarios**:

1. **Given** the Providers tab is open, **When** the user adds a provider, **Then** the Apple kind is offered (labelled as requiring macOS 27 when the Mac runs an older version), and choosing it hides or disables the credential and address fields and shows that the provider runs on this Mac with no network.
2. **Given** the user saves an Apple provider, **When** the configuration is written, **Then** it contains no credential reference and no endpoint address, and no Keychain entry is created.
3. **Given** the configuration file declares a provider with the Apple kind, **When** the configuration loads, **Then** the provider is registered and actions can select it.
4. **Given** an existing provider of another kind with a stored key, a model other than `system`, and any Base URL (even an invalid one) is edited and switched to the Apple kind, **When** the kind changes, **Then** the model field becomes `system`; **and when** it is saved, **Then** the save succeeds, its stored key is removed (unless another provider uses the same Keychain item, which is kept) and no address is kept; **and when** the user switches the kind back before saving, **Then** the model field shows the earlier model again.
5. **Given** a hand-edited Apple provider record that carries an address or a credential reference, **When** it is loaded and used, **Then** both are ignored and no network request is made.

---

### User Story 3 - Clear errors when the model cannot run (Priority: P1)

When the on-device model cannot serve a request, the user sees a specific, human-readable reason and what to do about it, and the selection is untouched. The reasons that matter are: the macOS version is too old, the Mac is not eligible for Apple Intelligence, Apple Intelligence is turned off, the model is still downloading or not ready, the selection is too long for the model, the model's safety rules refused the content, the model reports that it does not support the text's language, or the system limited how often Overtype may call the model.

**Why this priority**: Unlike a cloud provider, most failures here are caused by the device state, and each has a different fix (update macOS, turn on Apple Intelligence in System Settings, wait for the download, shorten the selection). A generic error would leave the user unable to act, which violates the "no silent failure" rule.

**Independent Test**: For each condition that can be produced on a test machine (Apple Intelligence off, an over-long selection, content the model refuses, an unsupported language), trigger an Apple action and confirm the specific message appears and the selection is unchanged. For conditions that cannot be produced on demand (ineligible device, old macOS, model not ready), confirm the mapping through unit tests of the error translation.

**Acceptance Scenarios**:

1. **Given** macOS is older than macOS 27, **When** the user runs an Apple action, **Then** an error states that the Apple provider requires macOS 27 or later, and the selection is unchanged.
2. **Given** Apple Intelligence is turned off, **When** the user runs an Apple action, **Then** an error says Apple Intelligence must be turned on in System Settings, and the selection is unchanged.
3. **Given** the Mac is not eligible for Apple Intelligence, **When** the user runs an Apple action, **Then** an error says this Mac does not support the on-device model.
4. **Given** the model is still downloading or otherwise not ready, **When** the user runs an Apple action, **Then** an error says the model is not ready yet and to try again later.
5. **Given** the selection plus the action's prompt is too long for the model, **When** the action runs, **Then** an error says the selection is too long for the on-device model, and nothing is written.
6. **Given** the model's safety rules block the request or the model refuses, **When** the action runs, **Then** an error says the on-device model declined to process this text, and nothing is written.
7. **Given** the model reports that the text's language is unsupported, **When** the action runs, **Then** an error names the language problem, and nothing is written.
8. **Given** the system rate-limits Overtype's use of the model, **When** the action runs, **Then** the run gets at most the one automatic retry that transient failures already get, only when the limit ends within 5 seconds, after waiting until it ends; otherwise, or if the retry also fails, the user sees a specific "temporarily limited" error.

---

### User Story 4 - Generation settings that fit the model (Priority: P2)

A user editing an action that uses the Apple provider sees the same "Automatic" creativity and reasoning controls as for other providers, and the "Automatic (...)" caption tells them what will actually be sent. Only settings the on-device model accepts are offered, and Automatic picks the fastest acceptable behaviour, because Overtype rewrites text while the user waits.

**Why this priority**: The model-aware parameter rules (feature 010) apply to every provider. Without a profile for the Apple model, the editor would show misleading options or the run would send settings the model rejects. It is P2 because P1 works with Automatic values alone.

**Independent Test**: Open the Actions editor for an action bound to an Apple provider and confirm the offered reasoning values and the Automatic caption match the Apple profile; run the action with Automatic and with an explicit value and confirm both succeed.

**Acceptance Scenarios**:

1. **Given** an action bound to an Apple provider with Automatic settings, **When** the editor shows the caption, **Then** it names exactly the values the run will use.
2. **Given** the Apple model does not support a reasoning setting, **When** the editor is shown, **Then** no reasoning values are offered for it.
3. **Given** an action sets an explicit creativity value, **When** it runs against the Apple provider, **Then** the value is always passed to the model; the model accepts any value, so none is withheld.

---

### Edge Cases

- **Overtype is a background accessory app.** The target application, not Overtype, is frontmost during every run. If the operating system restricts or rate-limits model use by apps that are not in the foreground, the feature fails in normal use. This MUST be verified by a recorded diagnostic run on a real machine before the plan is final (Principle III), and the result recorded in `docs/compatibility.md`.
- A configuration with the Apple kind is loaded on macOS 13 to 26. It MUST load without error and the provider MUST be listed; only running it produces the "requires a newer macOS" error. The configuration MUST NOT be rewritten or the provider dropped.
- The configured model name is empty, `system`, or something else. Empty and `system` both use the on-device system model; any other name produces a specific error naming the model instead of silently falling back.
- The model is available when Settings is open but becomes unavailable before the run (for example, Apple Intelligence is turned off). Availability is checked at the start of each run, not cached.
- The user presses Escape during a long generation. Generation stops promptly and no partial result is written.
- The provider time limit is reached during generation. The run ends with the standard timeout error and the selection is unchanged.
- The model output is empty or only whitespace. The standard "empty response" error applies.
- The model output contains a preamble or quotation marks around the answer. The existing response cleaning applies the same way as for other providers.
- Two Apple runs cannot overlap, because Overtype already runs one action at a time; each run uses a fresh model session with no memory of earlier runs, so one user's text never leaks into the next prompt.
- A hand-edited Apple record sets a non-default time limit or retry pause. Both are honoured as for other kinds.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST offer a new provider kind for Apple's on-device foundation model, selectable in configuration and in the Settings Providers tab.
- **FR-002**: The Apple provider MUST call the model through Apple's public, documented application interface for the on-device model. It MUST NOT launch the `fm` command-line tool or any other subprocess, and MUST NOT talk to a local server.
- **FR-003**: The Apple provider MUST make no network request of its own. Its configuration MUST NOT require or use an endpoint address or a credential.
- **FR-004**: The application MUST keep its current minimum macOS version (13). The Apple provider runs on macOS 27 and later only. On macOS 13 to 26, the Apple kind MUST still load from configuration and appear in the Settings picker labelled as requiring macOS 27, and running it MUST produce a specific typed error saying macOS 27 or later is required.
- **FR-005**: Before each request the provider MUST check the model's availability and map each unavailability reason (device not eligible, Apple Intelligence not enabled, model not ready, and any reason the system adds later) to a specific typed error with a message that tells the user what to do.
- **FR-006**: The provider MUST map these model failures to specific typed errors: input too long for the model, safety rules triggered, model refusal, unsupported language, rate limited, generation timeout, and model assets unavailable. Any other model failure MUST map to a typed error that still identifies the Apple provider as the source.
- **FR-007**: The automatic-retry classification MUST treat device-state errors (old macOS, ineligible device, Apple Intelligence off, model not ready), input too long, safety and refusal, and unsupported language as permanent, so they never consume the retry. Rate limiting MUST be treated as transient and get the single existing retry when the limit ends within 5 seconds or the system gives no end time; the pause before that retry MUST last until the reported end time. A limit that ends later MUST NOT be retried.
- **FR-008**: Pressing Escape MUST stop generation and cancel the run; the provider time limit MUST bound every request. Neither may write a partial result.
- **FR-009**: Each run MUST start a fresh model session that carries the action's system prompt as instructions and the rendered user prompt as the request, with no history from earlier runs.
- **FR-010**: Model selection MUST follow the existing order (action model, then provider default model). The Apple kind MUST accept a documented identifier for the default on-device model, pre-filled in Settings and used when the field is empty. The Actions editor MUST warn when an action that uses an Apple provider sets a model override other than empty or `system`, because every run of it would fail.
- **FR-011**: The Apple kind MUST have a model profile under the model-aware parameter rules: it states whether a creativity value is accepted and its range, which reasoning values (if any) are accepted, and the fastest value Automatic chooses. The editor caption and the request MUST come from the same resolver, as for the existing kinds. Profile values MUST be taken from a recorded diagnostic run against the real model, not from documentation alone.
- **FR-012**: The Settings Providers tab MUST, for the Apple kind, not ask for a credential or an address, show that the provider runs on this Mac without network, remove any stored credential when a provider is switched to the Apple kind, save successfully with both fields empty, and not validate a Base URL left over from another kind (the field is hidden, so it could not be fixed). Saving an Apple provider with a model other than `system` MUST be refused with a specific message. When a provider being added or edited is switched to the Apple kind and its model is neither empty nor `system`, the form MUST set the model to `system`, and MUST restore the earlier model if the kind is switched away again before saving; a new Apple provider MUST start with a 60-second timeout. A stored Keychain item MUST be deleted only on a kind change and only when no other provider names the same item. The model replacement is a narrow exception to feature 010's rule that editing never changes a provider's model, because the Apple kind has exactly one model (user decision 2026-11-19).
- **FR-013**: Every Apple run MUST use Apple's "permissive content transformations" safety mode, which Apple intends for transforming text the user supplies, so that ordinary text is not refused merely because of its subject. The mode is fixed; there is no setting for it.
- **FR-014**: Errors from the Apple provider MUST NOT log the selected text or the model output at `info` level or above, following the existing logging rules.
- **FR-015**: The project documentation MUST state that the Apple provider keeps the text on the Mac (`docs/privacy.md`), describe how to set it up including the Apple Intelligence requirement (`README.md`), and record the manual acceptance results (`docs/compatibility.md`).
- **FR-016**: The application MUST still build with the project's supported toolchain and pass its tests in continuous integration.

### Key Entities

- **Apple provider record**: A provider configuration with the Apple kind, an identifier, a display name, a default model identifier, a time limit and a retry pause. It has no endpoint address and no credential reference.
- **Model availability**: The state the operating system reports for the on-device model at the moment of a run: available, or unavailable with a reason.
- **Apple model profile**: The model-aware parameter entry for the on-device model: accepted creativity range, accepted reasoning values, fastest value, and the source and date of the evidence.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On an eligible Mac with Apple Intelligence on, a user can add an Apple provider and run a grammar action against it in under 1 minute, with no key, no address and no extra software.
- **SC-002**: A grammar fix of a 300-character selection completes, from shortcut to written text, in under 3 seconds on the test machine once the model is ready.
- **SC-003**: With all network interfaces off, 100% of Apple runs in the manual acceptance procedure succeed.
- **SC-004**: Every unavailability reason and every mapped model failure produces a distinct, specific message; 0 of them leave the selection modified.
- **SC-005**: Pressing Escape during generation leaves the selection unchanged in 100% of attempts and the HUD shows the cancelled state within 1 second.
- **SC-006**: On macOS versions older than 27, a configuration with an Apple provider loads with 0 warnings and every other provider keeps working.

## Assumptions

- Scope is the on-device model only. Apple's Private Cloud Compute model, which sends text to Apple servers and needs an iCloud account, is out of scope for this feature and can be added later as a separate decision under the privacy principle.
- The `fm` command-line tool and its `fm serve` server are not used. The user chose the public framework because the tool's terms forbid programmatic access to Apple models except as expressly permitted.
- The Apple provider requires macOS 27 (see Clarifications). The plan confirms that the CI toolchain has an SDK that can build it, and how the code compiles on a toolchain without that SDK.
- The on-device model has a small context window (4,096 tokens on macOS 26; the plan confirms the macOS 27 value at run time). The default action limit of 5,000 characters is assumed to fit together with a typical prompt and answer; a longer selection produces the "too long" error rather than truncated output.
- The Settings Providers tab needs a small change for the Apple kind (as it did for Ollama in feature 008). This is user-interface work, not part of the three-edit backend rule, and the plan's Constitution Check records it.
- Overtype runs one action at a time, so concurrent requests to the model are not a concern.
- The test machine runs macOS 27.2 with the system model ("AFM 3 Core Advanced") available, which covers the success path and the over-long, refusal and language cases; old-macOS and ineligible-device paths are verified by unit tests of the error mapping only.

## Revisions

### Revision: Implementation Sync 2026-11-19 [Sync: apple-settings-and-ci-pin]
- Reason: Implementation pass 2 shipped two Settings decisions for the Apple kind: the model becomes `system` when an existing provider switches to Apple, and the hidden Base URL is not validated on save.
- Items: User Story 2 scenario 4 ("Given an existing provider of another kind with a stored key"), FR-012
- Approved: approve all

### Revision: Implementation Sync 2026-11-19 [Sync: apple-review-fixes]
- Reason: Review rounds 1 and 2 changed shipped behaviour: rate-limit retries depend on the reset time and wait for it, Settings accept only the model `system` for Apple, replace and restore the model on a kind switch, pre-fill 60 s, keep shared Keychain items, and the Actions editor warns about an Apple model override.
- Items: FR-007, FR-010, FR-012, User Story 2 scenario 4 ("Given an existing provider of another kind with a stored key"), User Story 3 scenario 8 ("Given the system rate-limits Overtype's use of the model")
- Approved: "all" (user answer to the multi-model review round 2, item 2, 2026-11-19)
