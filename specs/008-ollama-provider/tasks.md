---

description: "Task list for 008-ollama-provider"
---

# Tasks: Local Ollama Model Support

**Input**: Design documents from `/specs/008-ollama-provider/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ollama-chat.md, quickstart.md

**Tests**: Test tasks ARE included. Constitution Principle VIII requires unit
tests for pure logic, and this feature adds a large amount of it (request body
construction, the pre-send size check, response parsing, reasoning stripping,
error extraction and mapping, endpoint construction, retry classification).
System-boundary work is covered by the manual acceptance procedure instead,
never by mocks.

**Revision, 2026-08-06**: revised after the cross-artifact analysis. Changes from
the first version: the three-case error set (was two) and the new FR-010b
pre-send refusal, a reasoning model promoted from a conditional to a
prerequisite, an assertion that the credential header is built correctly, and a
negative assertion on the request body's key set. Task IDs were renumbered.

**Organization**: Tasks are grouped by user story so each story is an
independently testable increment.

**Implementation status, 2026-08-06**: 27 of 32 tasks complete. All code, tests,
and documentation are done; `swift test` reports 229 tests with 0 failures.

Five review rounds were applied after the first implement pass. The second found
two real data-loss paths that the first version of this feature had shipped past:
the 12000-character input bound was derived from an English token ratio and did
not hold for CJK, and `num_ctx` was sized for the prompt alone although it also
covers the answer. Both are fixed (window 16384, bound 6000) and recorded in
research R3. A third fix removed `.networkConnectionLost` from the
`serviceUnreachable` mapping, since a dropped connection proves the service was
reachable.

The five unchecked tasks (T016, T021, T026, T028, T030) are **manual acceptance
runs only**. They require a human to select text in a real application and press
the action shortcut, which cannot be driven headlessly, and O10 additionally
requires disabling every network interface. What could be verified without a
human was verified and is recorded in `docs/compatibility.md`: the provider was
driven live against a running Ollama (happy path, unknown model, unreachable
service, reasoning model), the App Transport Security question was settled from
inside the built bundle, and the request/response contract was captured from the
real service rather than assumed. Each acceptance item in `docs/compatibility.md`
states which level of verification it received. The remaining end-to-end runs
must be completed before this feature ships in a release.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different file, no dependency on an incomplete task)
- **[Story]**: US1-US4 from spec.md
- Exact file paths are included in every task

## Path Conventions

Single native macOS app built with Swift Package Manager. Sources live under
`Sources/Overtype/`, tests under `Tests/OvertypeTests/`, docs under `docs/`.

---

## Phase 1: Setup

**Purpose**: Confirm a green starting point and prepare the environment the
acceptance run will need.

- [X] T001 Establish the green baseline: run `make test` and `make lint` at the repo root and record that they pass before any change (use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if `swift test` reports `no such module 'XCTest'`)
- [X] T002 [P] Prepare the acceptance environment per the Prerequisites section of `specs/008-ollama-provider/quickstart.md`: start the service with `ollama serve`, verify `curl -s http://localhost:11434/api/version` answers, run `ollama pull llama3.2` **and** `ollama pull deepseek-r1:1.5b` (the second is required by acceptance item O12, which verifies that a real reasoning model's output is filtered — without it SC-006 can only be half verified), and confirm both appear in `ollama list`. If `llama3.2` is no longer distributed, pick a substitute that is small, does not reason by default, and is generally available, then update `specs/008-ollama-provider/research.md` R11 and `specs/008-ollama-provider/quickstart.md` together

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared error type must carry the three new failure kinds before
the provider can map anything onto them. This is Exception IV-b in `plan.md`.

**⚠️ CRITICAL**: No user story work can begin until T003 compiles.

- [X] T003 Add `serviceUnreachable(address: String)`, `modelNotAvailable(model: String)` and `inputTooLargeForContext(limit: Int)` to `enum ProviderError` in `Sources/Overtype/Providers/AIProvider.swift`, handling all three in the three exhaustive switches: `errorDescription` (name the address / the model / the character limit and state the fix), `logLabel` (`"service unreachable"`, `"model not available"`, `"input too large for context"` — payload-free per Principle V), and `isRetryable` (all three `false`). Do not modify `retryableURLErrorCodes` — its `.cannotConnectToHost` entry must keep its current meaning for the other three providers
- [X] T004 Add retry-classification tests for all three new cases in `Tests/OvertypeTests/TransformRetryTests.swift`, asserting each is non-retryable and therefore triggers no second request

**Checkpoint**: The shared error type is ready; user stories can proceed.

---

## Phase 3: User Story 1 - Run an action against a local model (Priority: P1) 🎯 MVP

**Goal**: A configured Ollama action rewrites the selection using a model
running on the user's machine, with the standard feedback and cancellation.

**Independent Test**: With the service running and `llama3.2` installed, select
a sentence in TextEdit, press the action shortcut, and see the selection
replaced (quickstart O1, O2).

### Implementation for User Story 1

- [X] T005 [US1] Create `Sources/Overtype/Providers/OllamaProvider.swift` conforming to `AIProvider`: `id`, stored `ProviderConfig`, an ephemeral `URLSession` configured from `timeoutSeconds`, `defaultBaseURLString = "http://localhost:11434"` held as a `String` so the file contains no force unwrap (mirrors `AnthropicProvider`), and the two constants `contextWindowTokens = 16384` and `maxSafePromptTokens = 6000` (values revised after code review; see research R3)
- [X] T006 [US1] Implement `static func endpointURL(base: URL?) throws -> URL` in `Sources/Overtype/Providers/OllamaProvider.swift`, producing `{base}/api/chat` with trailing-slash normalisation and throwing `.invalidURL` on a malformed value
- [X] T007 [US1] Implement `static func requestBody(model:systemPrompt:userPrompt:temperature:) -> [String: Any]` in `Sources/Overtype/Providers/OllamaProvider.swift` exactly per `contracts/ollama-chat.md`: system and user entries in `messages`, `stream: false`, `options.temperature`, `options.num_ctx = 16384`. Add the three required inline comments — why `stream: false` is load-bearing (FR-010), why `num_ctx` is fixed and what it trades off (research R3), and why `temperature` IS sent here although `AnthropicProvider` deliberately omits it (research R4)
- [X] T008 [US1] Implement `static func checkInputSize(systemPrompt:userPrompt:) throws` in `Sources/Overtype/Providers/OllamaProvider.swift`, throwing `inputTooLargeForContext(limit: maxSafePromptTokens)` when the estimated tokens of the composed prompt exceed the bound (FR-010b). *(Signature and measure revised in review rounds 3 and 4: the check measures the composed prompt, not the raw selection, and estimates tokens rather than counting Characters — see research R3 and R13.)* Comment how the constant is derived from `contextWindowTokens` and why erring low is the safe direction: the failure mode of a low estimate is a visible refusal, of a high one is the user's text being silently shortened by the service
- [X] T009 [US1] Implement `static func stripLeadingReasoningBlock(_ text: String) -> String` in `Sources/Overtype/Providers/OllamaProvider.swift` per the contract table: remove a `<think>…</think>` or `<thinking>…</thinking>` block only when it starts the trimmed content, case-insensitive on the tag name, leaving a mid-text marker untouched, and yielding empty when the opening marker has no match. Comment it as FR-009 layer 2, scoped to Ollama only
- [X] T010 [US1] Implement `static func parseResponseText(from data: Data) throws -> String` in `Sources/Overtype/Providers/OllamaProvider.swift`: read `message.content` only, never `message.thinking`, apply `stripLeadingReasoningBlock`, throw `.emptyResponse` when nothing remains and `.invalidResponse` when the shape is wrong. Comment the allow-list as FR-009 layer 1
- [X] T011 [US1] Implement `transform(_:)` in `Sources/Overtype/Providers/OllamaProvider.swift` composing T006-T010: call `checkInputSize` **first**, before any URL or body is built, then render `{{text}}` into the user prompt, POST the body, and attach `Authorization: Bearer <key>` **only** when `keychainKey` is set and Keychain retrieval returns a non-empty value. Never throw `.apiKeyMissing`. Add the comment required by research R8 naming why: `SettingsViewModel.saveProvider` assigns a `keychainKey` to every provider it creates but writes the Keychain entry only when the key field was non-empty, so key presence must never be read as key required
- [X] T012 [US1] Replace the `case .ollama: break` stub in `Sources/Overtype/Providers/ProviderRegistry.swift` with `providers[config.id] = OllamaProvider(config: config)`, removing the "To be implemented in US3" comment
- [X] T013 [US1] Create `Tests/OvertypeTests/OllamaProviderTests.swift` covering the pure logic from T006-T010: endpoint construction with and without a trailing slash and with a custom port; the request body field by field, **including a negative assertion that its key set is exactly the expected one** so a later edit cannot silently reintroduce `keep_alive`, `think` or `num_predict` (FR-011); `checkInputSize` accepting a selection at the bound and rejecting one above it; the full `stripLeadingReasoningBlock` table from the contract; and `parseResponseText` for a normal answer, a `thinking`-bearing response, an empty answer, and a malformed body
- [X] T014 [US1] Add a credential-header test to `Tests/OvertypeTests/OllamaProviderTests.swift` covering the path no acceptance item exercises (every acceptance run is keyless): factor the header construction in `Sources/Overtype/Providers/OllamaProvider.swift` into a pure helper if needed, then assert that a non-empty credential produces exactly one `Authorization: Bearer <value>` header and that nil / empty produce none (FR-006)
- [X] T015 [US1] Run `make test` and `make lint`; all existing tests plus the new file must pass
- [ ] T016 [US1] Execute acceptance items O1 and O2 from `specs/008-ollama-provider/quickstart.md` against the built bundle (`./scripts/build-app.sh`, then open `Overtype.app`, re-granting Accessibility because the signature changed) and note the results for the later record

**Checkpoint**: User Story 1 is fully functional — an Ollama action rewrites a
selection end to end, and an oversized selection is refused rather than
truncated.

---

## Phase 4: User Story 2 - Choose Ollama without writing code and without a key (Priority: P1)

**Goal**: Ollama is selectable in Settings with no credential required, and a
hand-written config record is registered and usable.

**Independent Test**: Add the provider through Settings with the key field left
empty, and separately through `config.json` alone, and run an action from each
(quickstart O3, O4, O5).

### Implementation for User Story 2

- [X] T017 [US2] In `Sources/Overtype/UI/Settings/ProvidersTab.swift`, add `.ollama` to `selectableKinds`, change `kindLabel` for `.ollama` from `"Ollama (not implemented)"` to `"Ollama"`, and change `baseURLPlaceholder` for `.ollama` to `"Default: http://localhost:11434"`. Update the `selectableKinds` doc comment, which currently states that Ollama is an unimplemented stub and stays hidden, and the `baseURLPlaceholder` doc comment, which currently states that the Ollama hint is only a placeholder for a hidden kind — both become false with this change. This file is Exception IV-a in `plan.md`
- [X] T018 [US2] In `Sources/Overtype/UI/Settings/ProvidersTab.swift`, make the API-key `SecureField` prompt depend on the selected kind so it reads as optional for Ollama (for example `"API Key (optional, not needed for a local service)"`), keeping the existing add/edit wording for the other kinds. No change to `SettingsViewModel.saveProvider` is needed — it already accepts an empty key
- [X] T019 [P] [US2] Add an Ollama decode test to `Tests/OvertypeTests/AppConfigTests.swift`: a provider record with `kind: "ollama"`, a `defaultModel`, no `baseURL`, and no `keychainKey` decodes with `baseURL == nil` and `keychainKey == nil`, and round-trips through encode
- [X] T020 [US2] Update `README.md`: replace the "(Ollama support coming soon)" clause on line 10, and add a copy-ready Ollama recipe next to the existing provider recipes — the provider block from `specs/008-ollama-provider/data-model.md` (`kind: "ollama"`, `defaultModel: "llama3.2"`, `timeoutSeconds: 30`, no `baseURL`, no `keychainKey`), a statement that no API key is needed, the prerequisite that the user installs the service and pulls the model themselves, a note that the first run after an idle pause is slower because the model is being loaded (pointing at the service's own keep-alive setting), and a note that a first-run timeout is expected on slower hardware or larger models with raising the provider time limit as the fix
- [ ] T021 [US2] Run `make test` and `make lint`, then execute acceptance items O3, O4 and O5 from `specs/008-ollama-provider/quickstart.md` and note the results

**Checkpoint**: Both configuration paths work, and neither asks for a credential.

---

## Phase 5: User Story 3 - Clear, specific errors for local failures (Priority: P2)

**Goal**: A service that is not running, a model that is not installed, and a
selection too large for the context window each produce a specific error naming
what the user must fix, with no wasted retry.

**Independent Test**: Stop the service and run the action; restart it and run
with a model name that was never pulled; run with an oversized selection
(quickstart O7, O8, O9, O16).

### Implementation for User Story 3

- [X] T022 [US3] Implement `static func extractErrorMessage(from data: Data) -> String` in `Sources/Overtype/Providers/OllamaProvider.swift` handling Ollama's `{"error": "<string>"}` shape and delegating to `OpenAICompatibleProvider.extractErrorMessage(from:)` otherwise, so the existing truncated-raw-body fallback is reused rather than duplicated
- [X] T023 [US3] Implement `static func isModelNotFound(status: Int, body: Data) -> Bool` in `Sources/Overtype/Providers/OllamaProvider.swift` keying on status 404 **and** `"not found"` appearing in the extracted message, and wire the non-200 path in `transform(_:)` to throw `modelNotAvailable(model:)` carrying the **requested** model from the request (never a fragment parsed out of the server string, per Principle V) or `.apiError(statusCode:message:)` otherwise
- [X] T024 [US3] Implement `static func mapTransportFailure(_ error: Error, address: String) -> ProviderError` in `Sources/Overtype/Providers/OllamaProvider.swift` mapping `URLError.cannotConnectToHost` and `.cannotFindHost` to `serviceUnreachable(address:)` *(`.networkConnectionLost` was removed in review round 2: a dropped connection proves the service was reachable, so it must stay transient)* and delegating everything else to `ProviderError.mapTransportError` so timeout and cancellation keep their existing meaning; wire it into the `catch` around the `URLSession` call in place of the direct `mapTransportError` call. Comment that this is the only place a provider overrides the shared transport mapping and why it is confined here (research R6)
- [X] T025 [US3] Extend `Tests/OvertypeTests/OllamaProviderTests.swift` with error-path cases: the string-shaped error body extracts correctly, a non-JSON body falls back, `isModelNotFound` accepts 404 + "not found" and rejects a 404 without it and a 500 with it, and `mapTransportFailure` returns `serviceUnreachable` for the three connection codes while leaving `.timedOut` and `.cancelled` mapped as before
- [ ] T026 [US3] Run `make test` and `make lint`, then execute acceptance items O7, O8, O9 and O16 from `specs/008-ollama-provider/quickstart.md`, confirming in O7, O8 and O16 that no retry pause is observed and that O16 sends nothing at all, and note the results

**Checkpoint**: Every local failure mode reports its real cause.

---

## Phase 6: User Story 4 - Keep the text on the machine (Priority: P3)

**Goal**: An Ollama run works with no network at all and contacts nothing but
the configured endpoint, and the documentation says so.

**Independent Test**: Disconnect every network interface and run the action
(quickstart O10, O11).

### Implementation for User Story 4

- [X] T027 [P] [US4] Update `docs/privacy.md` to add Ollama as a destination, stating that with an Ollama provider the selected text is sent only to the provider's configured endpoint, which in the documented setup is the user's own machine, and that no other host is contacted
- [ ] T028 [US4] Execute acceptance items O10 and O11 from `specs/008-ollama-provider/quickstart.md` — the offline run and the endpoint observation — and note the results

**Checkpoint**: The local-only claim is verified rather than asserted.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T029 Execute acceptance item O6 from `specs/008-ollama-provider/quickstart.md`: run against `http://localhost:11434` from the built bundle and check the error code. Only if it reports `-1022` (`NSURLErrorAppTransportSecurityRequiresSecureConnection`), add `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true` to `Sources/Overtype/Resources/Info.plist` with a comment naming this feature and research R9, then rebuild and re-run. `NSAllowsArbitraryLoads` must not be used. If the run succeeds without the key, record that the key was not needed and leave `Info.plist` untouched
- [ ] T030 Execute the remaining acceptance items from `specs/008-ollama-provider/quickstart.md`: O12 (run an action against `deepseek-r1:1.5b`, pulled in T002, and confirm no reasoning text and no `<think>` markers reach the document — if that model could not be pulled, record O12 as **not executed**, never as passed, and say so in T031), O13 (nothing sensitive in logs at the default level, using `/usr/bin/log` because the bare `log` is shadowed by a zsh builtin), O14 (an existing OpenAI/Gemini/Anthropic action is unaffected), and O15 (a full-size selection at the default 5000-character limit is rewritten whole)
- [X] T031 Record the full Ollama acceptance run in `docs/compatibility.md` as a new section listing O1-O16 with their results and the date, including any item recorded as not executed and why
- [X] T032 Run the constitution PR checklist at the repo root: `rg NSPasteboard Sources/` returns nothing outside comments, `make lint` and `make test` pass, no secret / selected text / model output is logged at `info` or above, and every new boundary or quirk workaround carries its comment

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies. T002 is environment preparation and can happen at any point before the first acceptance task (T016)
- **Foundational (Phase 2)**: T003 blocks every story, because the provider maps onto the three new cases and the file will not compile without them. T004 depends on T003
- **US1 (Phase 3)**: depends on Phase 2. Delivers the MVP
- **US2 (Phase 4)**: depends on Phase 2 for compilation and on T012 for a runnable end-to-end check; the Settings edits themselves (T017-T018) touch a different file and do not depend on the provider
- **US3 (Phase 5)**: depends on US1, because T022-T024 extend the same provider file and wire into `transform(_:)`
- **US4 (Phase 6)**: T027 depends on nothing; T028 depends on US1 being runnable
- **Polish (Phase 7)**: depends on all stories

### Within Each User Story

- Pure-logic helpers before `transform(_:)` composes them
- `checkInputSize` runs first inside `transform(_:)`, before any URL, body, or Keychain access, so an oversized selection costs nothing and touches nothing
- Implementation before its unit tests are run, but the test file may be authored alongside
- Unit tests green before the acceptance items of the same story are executed

### Parallel Opportunities

- T002 runs in parallel with everything up to T016
- T019 (`AppConfigTests.swift`) is independent of the provider file and of the Settings file, so it can run alongside T017-T018
- T027 (`docs/privacy.md`) is independent of all code and can be written at any time after Phase 2
- T017-T018 (`ProvidersTab.swift`) and T005-T014 (`OllamaProvider.swift`) touch different files and can proceed in parallel once T003 is in
- Within `OllamaProvider.swift`, tasks are sequential: they all edit one file

## Parallel Example

```bash
# After T003 lands, these touch three different files:
Task: "T017 Settings picker edits in Sources/Overtype/UI/Settings/ProvidersTab.swift"
Task: "T019 Ollama config decode test in Tests/OvertypeTests/AppConfigTests.swift"
Task: "T027 Ollama destination note in docs/privacy.md"
```

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 Setup — confirm the baseline is green
2. Phase 2 Foundational — the three error cases (T003, T004)
3. Phase 3 US1 — the provider and the registry line
4. **STOP and VALIDATE**: O1 and O2 against the real service

At that point an Ollama action already works end to end through a hand-written
config record. US2 makes it reachable from Settings, US3 makes its failures
legible, US4 proves and documents the local-only property.

### Incremental Delivery

1. Setup + Foundational → shared error type ready
2. US1 → working local rewrite (MVP)
3. US2 → configurable without editing JSON, and without a key
4. US3 → specific errors for the three local failure modes
5. US4 → verified offline operation and updated privacy documentation
6. Polish → ATS decision, remaining acceptance items, recorded results

### Notes

- Commit after each task or logical group; do not commit acceptance notes until
  T031 records them in `docs/compatibility.md`
- Every acceptance item runs against the built bundle, not the raw executable,
  and Accessibility must be re-granted after each rebuild because the permission
  is bound to the code signature
- Seven inline comments are mandated by specific tasks (T007 ×3, T008, T009,
  T010, T011, T024). They exist because each records a decision that a later
  reader would otherwise "simplify" away, which the constitution forbids
