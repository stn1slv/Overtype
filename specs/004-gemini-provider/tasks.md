---
description: "Task list for Gemini Model Support"
---

# Tasks: Gemini Model Support

**Input**: Design documents from `/specs/004-gemini-provider/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: INCLUDED. The constitution (Principle VIII) and the spec require unit
tests for pure logic (response parsing, error mapping). System-boundary behavior
(live HTTP) is covered by manual acceptance in `quickstart.md`, not mocks.

**Organization**: Tasks are grouped by user story. US1 is the MVP.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1, US2, US3 (maps to spec.md user stories)
- Exact file paths are included in each task.

## Path Conventions

Single Swift Package project. Source under `Sources/Overtype/`, tests under
`Tests/OvertypeTests/`, docs under `docs/`, `README.md` at repo root.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm a green baseline before changing anything.

- [X] T001 Run `swift test` from repo root and confirm all existing tests pass (green baseline recorded before changes).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared type changes that every user story depends on. Both compile independently of the new provider.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Add `case gemini = "gemini"` to the `ProviderKind` enum in `Sources/Overtype/Config/AppConfig.swift`.
- [X] T003 [P] Add `case responseBlocked(reason: String)` and `case emptyResponse` to `ProviderError`, with specific human-readable `errorDescription` values (no secrets), in `Sources/Overtype/Providers/AIProvider.swift`.

**Checkpoint**: Enum and typed errors exist; the project still builds. User stories can begin.

---

## Phase 3: User Story 1 - Run an action against a Gemini model (Priority: P1) 🎯 MVP

**Goal**: A configured Gemini action reads the selection, calls Gemini's `generateContent`, and writes the result back through the existing pipeline.

**Independent Test**: With a Gemini provider + action configured, select text in a supported app, press the shortcut, and confirm the selection is replaced by Gemini output with Reading → Thinking → Writing feedback (quickstart A1).

### Tests for User Story 1 ⚠️ (write first, ensure they FAIL before T005-T007)

- [X] T004 [P] [US1] Add success-path unit tests in `Tests/OvertypeTests/GeminiProviderTests.swift`: a canned 200 `generateContent` body yields the extracted text, and multiple `candidates[0].content.parts[*].text` are concatenated in order. Target the pure parse function from T007.

### Implementation for User Story 1

- [X] T005 [US1] Create `GeminiProvider` conforming to `AIProvider` in `Sources/Overtype/Providers/GeminiProvider.swift`: store `ProviderConfig`, build an ephemeral `URLSession` using `config.timeoutSeconds`, and compute the request URL as `models/{model}:generateContent` against `config.baseURL` or the default base `https://generativelanguage.googleapis.com/v1beta/`.
- [X] T006 [US1] In `GeminiProvider.transform(_:)` build and send the request in `Sources/Overtype/Providers/GeminiProvider.swift`: read the key from the Keychain via `config.keychainKey` and set the `x-goog-api-key` header (throw `.apiKeyMissing` when absent/empty, before any network call); set `Content-Type: application/json`; build the JSON body (`systemInstruction.parts[].text`, `contents[0].parts[0].text` with `{{text}}` replaced by the selection, `generationConfig.temperature`); POST via URLSession. The key MUST NOT appear in the URL.
- [X] T007 [US1] Implement the success parse as a pure static function in `Sources/Overtype/Providers/GeminiProvider.swift`: concatenate `candidates[0].content.parts[*].text` and return the string; call it from `transform` and return its result into the existing pipeline (sanitizer runs in `ActionEngine`).
- [X] T008 [US1] Wire the provider into `ProviderRegistry.reloadProviders()` in `Sources/Overtype/Providers/ProviderRegistry.swift` with the single line `case .gemini: providers[config.id] = GeminiProvider(config: config)`.
- [X] T009 [US1] Run `swift test --filter GeminiProviderTests` and confirm the T004 success tests now pass; run full `swift test` to confirm no regression.

**Checkpoint**: Gemini happy path works end to end and the provider is registered.

---

## Phase 4: User Story 2 - Configure Gemini without writing code (Priority: P1)

**Goal**: A user enables Gemini by editing configuration and storing a key only; no Swift change or rebuild for the user. The shipped default config is unchanged.

**Independent Test**: Starting from a default install, add a `kind: gemini` provider block to `config.json`, store the key, point an action at it, and confirm it works without rebuilding (quickstart step 2 + A1).

### Tests for User Story 2 ⚠️

- [X] T010 [P] [US2] Add a config-decode unit test in `Tests/OvertypeTests/AppConfigTests.swift` (co-located with the existing config decode tests): a `ProviderConfig` JSON with `"kind": "gemini"` decodes to `ProviderKind.gemini` with `defaultModel` and `keychainKey` preserved. [Sync: Gap Report]

### Implementation for User Story 2

- [X] T011 [US2] Add the Gemini enablement recipe to `README.md` (a provider block with `kind: gemini`, `defaultModel: gemini-3.5-flash-lite`, `keychainKey`, plus how to store the key in the Keychain and point an action at it), and confirm the inline default in `Sources/Overtype/Config/DefaultConfig.swift` is left unchanged (no pre-seeded Gemini provider or shortcut).

**Checkpoint**: Gemini is reachable purely by configuration; first-run default is unchanged.

---

## Phase 5: User Story 3 - Clear, specific errors for Gemini failures (Priority: P2)

**Goal**: Every Gemini failure maps to a specific typed error and leaves the selection untouched.

**Independent Test**: Trigger a Gemini action with an invalid key, an unknown model, a safety-blocked input, and with the network down; confirm each shows a specific error and the selection is unchanged (quickstart A4-A8).

### Tests for User Story 3 ⚠️ (write first, ensure they FAIL before T013-T014)

- [X] T012 [P] [US3] Add error-mapping unit tests in `Tests/OvertypeTests/GeminiProviderTests.swift`: `promptFeedback.blockReason` body → `.responseBlocked`; a `finishReason == "SAFETY"` candidate → `.responseBlocked`; present-but-empty text → `.emptyResponse`; a non-200 body with `error.message` → `.apiError(statusCode:message:)`; a structurally unexpected body → `.invalidResponse`.

### Implementation for User Story 3

- [X] T013 [US3] Add non-200 and transport handling to `GeminiProvider.transform(_:)` in `Sources/Overtype/Providers/GeminiProvider.swift`: on non-200 extract `error.message` (fallback to a truncated raw body) and throw `.apiError(statusCode:message:)`; map `URLError` timeout to `.timeout` and other transport failures to `.networkError`.
- [X] T014 [US3] Extend the pure parse function in `Sources/Overtype/Providers/GeminiProvider.swift` to detect failures: `promptFeedback.blockReason` set, empty `candidates`, or `finishReason == "SAFETY"` / no text part → `.responseBlocked(reason:)`; a completed candidate with empty text → `.emptyResponse`; unexpected shape → `.invalidResponse`.
- [X] T015 [US3] Confirm `GeminiProvider` logs no selected text, model output, or key at `info`+; route any diagnostic through `Logger.shared.sanitizedLog(...)` at `.debug` in `Sources/Overtype/Providers/GeminiProvider.swift`.
- [X] T016 [US3] Run `swift test --filter GeminiProviderTests` and confirm all T012 error tests pass; run full `swift test`.

**Checkpoint**: All three user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, privacy verification, and manual acceptance before merge.

- [X] T017 [P] Update `docs/privacy.md` to state that selected text is sent to Google's Gemini endpoint (`generativelanguage.googleapis.com`) when a Gemini action runs.
- [X] T018 [P] Record the Gemini manual acceptance results (quickstart A1-A8) in `docs/compatibility.md`.
- [X] T019 Run the PR checklist: `rg NSPasteboard Sources/` returns no match outside comments; audit that no secret, selected text, or model output is logged at `info`+; confirm any boundary workaround carries a comment (none expected here).
- [ ] T020 Execute the manual acceptance procedure in `specs/004-gemini-provider/quickstart.md` (A1-A8) against a real supported app and record outcomes.
- [X] T021 Run full `swift test` from repo root and confirm green.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup. BLOCKS all user stories.
- **US1 (Phase 3)**: Depends on Foundational. Creates `GeminiProvider.swift` and the registry wiring (the MVP).
- **US2 (Phase 4)**: Depends on Foundational. The config-decode test needs only T002; end-to-end registration/validation also relies on US1's registry wiring (T008).
- **US3 (Phase 5)**: Depends on Foundational and on US1 (extends `GeminiProvider.swift` and its parse function created in T005-T007).
- **Polish (Phase 6)**: Depends on US1-US3 being complete.

### User Story Dependencies

- **US1 (P1)**: Independent after Foundational. Delivers the working happy path.
- **US2 (P1)**: Doc recipe + decode test are independent; full "provider registered and selectable" validation uses US1's wiring.
- **US3 (P2)**: Builds on US1's provider file; happy path (US1) remains testable without US3, and error paths (US3) are testable on their own.

### Within Each User Story

- Tests are written first and must FAIL before the matching implementation.
- Provider creation (T005) before request build (T006) before parse (T007) before registry wiring (T008), since they build on the same file.

### Parallel Opportunities

- T003 [P] runs alongside T002 (different files).
- T004 [P] (test file) can be written in parallel with starting US1 implementation.
- T010 [P] (config decode test) is independent of US1/US3 code.
- T012 [P] (error tests) can be written in parallel, before US3 implementation.
- T017 [P] and T018 [P] (separate doc files) run in parallel during Polish.

---

## Parallel Example: User Story 1

```bash
# Write the failing success tests while scaffolding the provider:
Task: "T004 Add success-path unit tests in Tests/OvertypeTests/GeminiProviderTests.swift"
# then implement T005 → T006 → T007 (same file, sequential) → T008 (registry).
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup (green baseline).
2. Phase 2: Foundational (enum case + error types).
3. Phase 3: US1 (provider + registry + success parse + tests).
4. **STOP and VALIDATE**: run quickstart A1 with a real key.
5. This is a shippable MVP: Gemini works for the happy path.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 → happy path works → validate (MVP).
3. US2 → documented enablement + decode test → validate config-only setup.
4. US3 → specific error handling → validate failure cases.
5. Polish → docs, privacy audit, manual acceptance.

---

## Notes

- [P] = different files, no dependency on incomplete tasks.
- Every failure path stays a typed `ProviderError` (Principle VI); the selection
  is never modified before a validated write (Principle II).
- The API key is only ever read from the Keychain and sent via the
  `x-goog-api-key` header (Principle V) — never in a URL, config, log, or UI.
- Commit after each task or logical group. Do not declare done with failing tests.
