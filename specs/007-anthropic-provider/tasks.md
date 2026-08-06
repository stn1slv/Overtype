---
description: "Task list for Anthropic Claude Model Support"
---

# Tasks: Anthropic Claude Model Support

**Input**: Design documents from `/specs/007-anthropic-provider/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: INCLUDED. The constitution (Principle VIII) and the spec require unit
tests for pure logic (response parsing, reasoning filtering, error mapping).
System-boundary behavior (live HTTP) is covered by manual acceptance in
`quickstart.md`, not mocks.

**Organization**: Tasks are grouped by user story. US1 is the MVP.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1, US2, US3 (maps to spec.md user stories)
- Exact file paths are included in each task.

## Path Conventions

Single Swift Package project. Source under `Sources/Overtype/`, tests under
`Tests/OvertypeTests/`, docs under `docs/`, `README.md` at repo root.

**All `swift test` invocations must be prefixed with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`** when the active
toolchain is Command Line Tools (`xcode-select -p`); without it the build fails
with `no such module 'XCTest'`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm a green baseline before changing anything.

- [X] T001 Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from repo root and confirm all existing tests pass (green baseline recorded before changes).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared type changes that every user story depends on.

**NONE REQUIRED.** This phase is deliberately empty, and that is a finding rather
than an omission. Unlike 004, which had to add a `ProviderKind` case and two
`ProviderError` cases before any story could start:

- `ProviderKind.anthropic` already exists in `Sources/Overtype/Config/AppConfig.swift`.
- `ProviderError.responseBlocked(reason:)` and `.emptyResponse` already exist in
  `Sources/Overtype/Providers/AIProvider.swift` (added by 004), and every
  Anthropic outcome maps onto the existing case set — see `research.md` R6.

Both files are therefore untouched by this feature, and user story work can begin
immediately after Setup.

**Checkpoint**: No blocking prerequisites. Proceed directly to US1.

---

## Phase 3: User Story 1 - Run an action against a Claude model (Priority: P1) 🎯 MVP

**Goal**: A configured Anthropic action reads the selection, calls the Messages
API, and writes only the answer text back through the existing pipeline.

**Independent Test**: With an Anthropic provider + action configured, select text
in a supported app, press the shortcut, and confirm the selection is replaced by
Claude output with Reading → Thinking → Writing feedback (quickstart A1).

### Tests for User Story 1 ⚠️ (write first, ensure they FAIL before T003-T006)

- [X] T002 [P] [US1] Add success-path unit tests in `Tests/OvertypeTests/AnthropicProviderTests.swift`: a canned 200 Messages body yields the extracted text; several `type: "text"` blocks concatenate in order; **a `type: "thinking"` block preceding the answer is skipped** (FR-008/SC-005); an unrecognised block type is skipped; `stop_reason: "max_tokens"` with non-empty text is a success. Also cover endpoint construction: default base yields `https://api.anthropic.com/v1/messages`, and a `baseURL` override works with and without a trailing slash. Target the pure static functions from T004 (`endpointURL`) and T006 (`parseResponseText`).

### Implementation for User Story 1

- [X] T003 [US1] Create `AnthropicProvider` conforming to `AIProvider` in `Sources/Overtype/Providers/AnthropicProvider.swift`: store `ProviderConfig`, expose `id`, build an ephemeral `URLSession` with `timeoutIntervalForRequest` and `timeoutIntervalForResource` both set from `config.timeoutSeconds`, and hold the default base as the `String` `https://api.anthropic.com/v1/` (not a force-unwrapped `URL`, so the file contains no `!`).
- [X] T004 [US1] Implement `static func endpointURL(base: URL?) throws -> URL` in `Sources/Overtype/Providers/AnthropicProvider.swift`: normalise the base to end in `/`, append `messages`, throw `.invalidURL` if the string will not parse. Note it takes **no model argument** — Anthropic carries the model in the request body, so none of `GeminiProvider`'s colon-escaping workaround is needed.
- [X] T005 [US1] In `AnthropicProvider.transform(_:)` build and send the request in `Sources/Overtype/Providers/AnthropicProvider.swift`: read the key from the Keychain via `config.keychainKey` and set the `x-api-key` header (throw `.apiKeyMissing` when the key reference is absent/empty, the Keychain throws, or the value is empty — all before any network call); set `anthropic-version: 2023-06-01` and `Content-Type: application/json`; build the JSON body (`model`, `max_tokens` from a private static constant `8192`, top-level `system` from `systemPrompt`, and `messages: [{role: "user", content: <userPromptTemplate with {{text}} replaced>}]`); POST via `URLSession`. **The key MUST NOT appear in the URL.** **`temperature` MUST NOT be sent** — add an inline comment naming the reason (see spec Clarifications) so it is not "helpfully" restored later. _(Correction 2026-08-06: this task originally said "current Claude models reject it with HTTP 400". Only the Opus 4.7/4.8, Opus 5, Sonnet 5 and Fable 5 generation do; `claude-haiku-4-5` still accepts it. The task as executed is unaffected — the parameter is omitted either way — but the shipped comment states the accurate premise.)_ Send no `thinking` or `effort` field, for the same per-model-staleness reason.
- [X] T006 [US1] Implement the success parse as pure static functions in `Sources/Overtype/Providers/AnthropicProvider.swift`: `parseResponseText(from:)` plus an `extractText(from:)` helper that concatenates, in order, the `text` of every `content` block whose `type` is exactly `"text"`, **skipping every other block type** (allow-list, not deny-list, so an unrecognised future block type is skipped rather than written into the user's document). Call it from `transform` and return its result into the existing pipeline (the sanitizer runs in `ActionEngine`).
- [X] T007 [US1] Wire the provider into `ProviderRegistry.reloadProviders()` in `Sources/Overtype/Providers/ProviderRegistry.swift` by replacing `case .anthropic: break` (and its `// To be implemented in US2` comment) with the single line `providers[config.id] = AnthropicProvider(config: config)`.
- [X] T008 [US1] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AnthropicProviderTests` and confirm the T002 tests now pass; run the full suite to confirm no regression.

**Checkpoint**: Anthropic happy path works end to end, reasoning never reaches the document, and the provider is registered.

---

## Phase 4: User Story 2 - Choose Anthropic without writing code (Priority: P1)

**Goal**: A user enables Anthropic from the Settings picker or by editing
configuration and storing a key; no Swift change or rebuild. The shipped default
config is unchanged.

**Independent Test**: From a default install, add an Anthropic provider via
Settings → Providers, and separately by adding a `kind: anthropic` block to
`config.json`; confirm both work without rebuilding (quickstart step 2 + A1).

### Tests for User Story 2 ⚠️

- [X] T009 [P] [US2] Add a config-decode unit test in `Tests/OvertypeTests/AppConfigTests.swift` (co-located with the existing config decode tests, matching where 004's equivalent landed): a `ProviderConfig` JSON with `"kind": "anthropic"` decodes to `ProviderKind.anthropic` with `defaultModel` (`claude-haiku-4-5`) and `keychainKey` preserved.

### Implementation for User Story 2

- [X] T010 [US2] Make Anthropic selectable in `Sources/Overtype/UI/Settings/ProvidersTab.swift`: add `.anthropic` to the `selectableKinds` list; change `kindLabel(_:)` to return `"Anthropic"` without the `(not implemented)` suffix; extend the base-URL placeholder (currently the two-way `kind == .gemini ? … : …`) into a form covering all three implemented kinds, with an Anthropic hint of `Default: api.anthropic.com`. `SettingsViewModel.saveProvider(...)` is kind-agnostic and needs no change.
- [X] T011 [US2] Add the Anthropic enablement recipe to `README.md` (a provider block with `kind: anthropic`, `defaultModel: claude-haiku-4-5`, `keychainKey: overtype-anthropic-key`, plus how to store the key and point an action at it), **state that the action's `temperature` does not apply to Anthropic runs**, update the feature line that currently says Anthropic support is "coming soon", and confirm the inline default in `Sources/Overtype/Config/DefaultConfig.swift` is left unchanged (no pre-seeded Anthropic provider or shortcut).
- [X] T012 [US2] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppConfigTests` and confirm the T009 decode test passes; build and open the app to confirm Anthropic appears in the Settings provider-kind picker without a "not implemented" label.

**Checkpoint**: Anthropic is reachable from the UI and by configuration; first-run default is unchanged.

---

## Phase 5: User Story 3 - Clear, specific errors for Anthropic failures (Priority: P2)

**Goal**: Every Anthropic failure maps to a specific typed error and leaves the
selection untouched, with transient failures receiving the existing single retry.

**Independent Test**: Trigger an Anthropic action with an invalid key, an unknown
model, a declined prompt, and with the network down; confirm each shows a
specific error and the selection is unchanged (quickstart A4–A8, A10).

### Tests for User Story 3 ⚠️ (write first, ensure they FAIL before T014-T015)

- [X] T013 [P] [US3] Add error-mapping unit tests in `Tests/OvertypeTests/AnthropicProviderTests.swift`: `stop_reason: "refusal"` → `.responseBlocked`, and with `stop_details.category` present the reason incorporates the category; another non-normal `stop_reason` (e.g. `pause_turn`) → `.responseBlocked`; a body whose only blocks are `thinking` → `.emptyResponse`; a body with an empty `text` block → `.emptyResponse`; a non-JSON body and a body missing `content` → `.invalidResponse`. Add an assertion that the constructed reason string never contains `stop_details.explanation`. **Also add an explicit `ProviderError.apiError(statusCode: 529, …).isRetryable == true` assertion** (in `Tests/OvertypeTests/ProviderErrorRetryTests.swift`, alongside the existing `[500, 502, 503, 504, 599]` loop): FR-011's entire no-code claim rests on Anthropic's 529 `overloaded_error` falling inside `500...599`, and 529 is currently never asserted anywhere.

### Implementation for User Story 3

- [X] T014 [US3] Add non-200 and transport handling to `AnthropicProvider.transform(_:)` in `Sources/Overtype/Providers/AnthropicProvider.swift`: cast to `HTTPURLResponse` or throw `.invalidResponse`; on non-200 throw `.apiError(statusCode:message:)` using the shared `OpenAICompatibleProvider.extractErrorMessage(from:)` (Anthropic's error envelope is also `{"error": {"message": …}}`); wrap the `URLSession` call so transport failures go through `ProviderError.mapTransportError(_:)`. Add a comment noting that no retry code is needed here because `ProviderError.isRetryable` already covers 429 and 5xx-except-501, which includes Anthropic's 529 `overloaded_error`.
- [X] T015 [US3] Extend `parseResponseText(from:)` in `Sources/Overtype/Providers/AnthropicProvider.swift` to detect failures: unparseable JSON or a missing/non-array `content` → `.invalidResponse`; `stop_reason` present and not one of `end_turn` / `max_tokens` / `stop_sequence` → `.responseBlocked(reason:)`, using `stop_details.category` to enrich a `refusal` when present and **deliberately ignoring `stop_details.explanation`** (server prose that may echo the submitted text; add a comment saying so); text empty after filtering → `.emptyResponse`. Guard the stop-reason check on the field being present so a body without one falls through to extraction.
- [X] T016 [US3] Confirm `AnthropicProvider` logs no selected text, model output, or key at `info`+; route any diagnostic through `Logger.shared.sanitizedLog(...)` at `.debug` in `Sources/Overtype/Providers/AnthropicProvider.swift`.
- [X] T017 [US3] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AnthropicProviderTests` and confirm all T013 error tests pass; run the full suite.

**Checkpoint**: All three user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, privacy verification, and manual acceptance before merge.

- [X] T018 [P] Update `docs/privacy.md` to state that selected text is sent to Anthropic's endpoint (`api.anthropic.com`) when an Anthropic action runs.
- [X] T019 [P] Add an `### Anthropic (native /v1/messages)` subsection under `## Provider Acceptance` in `docs/compatibility.md`, following the existing Gemini block: a paragraph naming what `AnthropicProviderTests` already covers and pointing at `specs/007-anthropic-provider/quickstart.md`, a `**Status: PENDING**` line, and an A1–A10 result table whose IDs match the quickstart one-for-one.
- [X] T020 Run the PR checklist: `rg NSPasteboard Sources/` returns no match outside comments; audit that no secret, selected text, or model output is logged at `info`+; confirm the two deliberate omissions (`temperature`, and any reasoning/effort field) each carry an explanatory comment; confirm FR-015 by checking `AnthropicProvider` issues exactly one URL and adds no telemetry or update-ping call.
- [ ] T021 Execute the manual acceptance procedure in `specs/007-anthropic-provider/quickstart.md` (A1–A10) against a real supported app with a real API key and record outcomes in `docs/compatibility.md`. _(Correction 2026-08-06: this task originally said A9 "must not be skipped — it is the only live check of FR-008". That was wrong. Because the provider sends no `thinking` field it cannot request summarised reasoning, and on the Claude 5 tier `thinking.display` defaults to `"omitted"`, so reasoning blocks arrive empty and A9 passes whether the filter works or not. FR-008 is gated by `AnthropicProviderTests`, which feeds synthetic non-empty reasoning blocks; A9 is an end-to-end smoke check only. See the A9 caveat in `quickstart.md`.)_
- [X] T022 Run the full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` from repo root and confirm green.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Empty — nothing blocks the user stories.
- **US1 (Phase 3)**: Depends on Setup. Creates `AnthropicProvider.swift` and the registry wiring (the MVP).
- **US2 (Phase 4)**: Depends on Setup. The config-decode test and the Settings edit are independent of US1; end-to-end registration also relies on US1's registry wiring (T007).
- **US3 (Phase 5)**: Depends on US1 (extends `AnthropicProvider.swift` and the parse function created in T005–T006).
- **Polish (Phase 6)**: Depends on US1–US3 being complete.

### User Story Dependencies

- **US1 (P1)**: Independent. Delivers the working happy path, including the reasoning filter.
- **US2 (P1)**: Settings edit, README recipe, and decode test are independent; full "provider registered and selectable" validation uses US1's wiring.
- **US3 (P2)**: Builds on US1's provider file. The happy path (US1) remains testable without US3, and error paths (US3) are testable on their own.

### Within Each User Story

- Tests are written first and must FAIL before the matching implementation.
- Provider scaffold (T003) → endpoint builder (T004) → request build (T005) → parse (T006) → registry wiring (T007), since T003–T006 build on the same file.

### Parallel Opportunities

- T002 [P] (test file) can be written in parallel with scaffolding US1.
- T009 [P] (config decode test) is independent of US1/US3 code and of T010.
- T013 [P] (error tests) can be written in parallel, before US3 implementation.
- T018 [P] and T019 [P] (separate doc files) run in parallel during Polish.
- All of Phase 4 can proceed in parallel with Phase 3, since it touches
  `ProvidersTab.swift`, `AppConfigTests.swift`, and `README.md` — no file US1 touches.

---

## Parallel Example: User Story 1

```bash
# Write the failing success + reasoning-filter tests while scaffolding the provider:
Task: "T002 Add success-path unit tests in Tests/OvertypeTests/AnthropicProviderTests.swift"
# then implement T003 → T004 → T005 → T006 (same file, sequential) → T007 (registry).
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup (green baseline).
2. Phase 2: nothing to do.
3. Phase 3: US1 (provider + endpoint + request + parse + reasoning filter + registry + tests).
4. **STOP and VALIDATE**: run quickstart A1 with a real key (and A9 as a smoke check — see its caveat; the reasoning filter itself is gated by the unit tests).
5. This is a shippable MVP: Anthropic works for the happy path and never writes reasoning.

### Incremental Delivery

1. Setup → baseline green.
2. US1 → happy path works → validate (MVP).
3. US2 → Settings picker + documented enablement + decode test → validate config-only and UI setup.
4. US3 → specific error handling → validate failure cases.
5. Polish → docs, privacy audit, manual acceptance.

---

## Notes

- [P] = different files, no dependency on incomplete tasks.
- Every failure path stays a typed `ProviderError` (Principle VI); the selection
  is never modified before a validated write (Principle II).
- The API key is only ever read from the Keychain and sent via the `x-api-key`
  header (Principle V) — never in a URL, config, log, or UI.
- **The two deliberate omissions (`temperature`, and any reasoning/effort field)
  must each keep their explanatory comment.** Both look like oversights to a
  future reader, and restoring either breaks the provider against current models.
- Commit after each task or logical group. Do not declare done with failing tests.

---

## Phase 7: Convergence

Appended by `/speckit-converge` after the first `/speckit-implement` pass. One
partial gap found; no missing, contradicting, or unrequested work.

- [ ] T023 Launch the built app and visually confirm the Settings → Providers kind picker offers "Anthropic" without a "not implemented" qualifier, and that saving an Anthropic provider with a key persists and survives a reload, per FR-002 / US1-AC1 of US2 (partial). Code-level verification and a clean build were done in T012; the running-UI half was not, so this closes it.

**Note on T021**: the live manual acceptance run (A1–A10) remains open by design
and is deliberately **not** duplicated here. It requires a real API key and real
target applications, so it cannot be completed by `/speckit-implement` — it is a
human release-gate step, already tracked in Phase 6 and recorded as
`**Status: PENDING**` in `docs/compatibility.md`, matching how 004's equivalent
still stands.
