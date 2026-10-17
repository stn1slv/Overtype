# Tasks: Model-Aware Generation Parameters

**Input**: Design documents from `/specs/010-model-aware-parameters/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/request-parameters.md, contracts/model-profiles.md, quickstart.md

**Tests**: Included. FR-025 and constitution Principle VIII require unit tests for all new pure logic. Within each story, test tasks come first and must fail before the implementation lands.

**Organization**: Grouped by user story from spec.md: US1 current models work (P1), US2 new default model (P1), US3 adaptive fallback for OpenAI (P1), US4 editor overrides (P2).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: User story the task belongs to

---

## Phase 1: Setup

- [X] T001 Record a green baseline: run `make test` (note the test count) and `rg NSPasteboard Sources/ Vendor/` (no match outside comments); no code changes

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The optional action fields and the provider-neutral request types that US1, US3 and US4 all build on.

**CRITICAL**: No user story work can begin until this phase is complete.

### Tests

- [X] T002 [P] Update and extend decode tests in Tests/OvertypeTests/AppConfigTests.swift: missing `temperature` decodes to `nil` (replaces the `0.0` assertion at line 159); wrong-typed `temperature` decodes to `nil` and records an issue (replaces the `0.0` assertion at line 232); `"temperature": 0` stays `0`; `reasoningEffort` decodes as text, blank or whitespace-only becomes `nil`, wrong type becomes `nil` plus an issue naming key and action id only; encoding an action with both fields `nil` omits both keys (data-model.md, ActionConfig)
- [X] T003 [P] Add a `nil`-temperature case to Tests/OvertypeTests/OllamaProviderTests.swift: `options` key set is exactly `["num_ctx"]`; keep the existing `["temperature", "num_ctx"]` assertion for a set temperature (contracts/request-parameters.md, Ollama)

### Implementation

- [X] T004 Make `ActionConfig.temperature` a `Double?` and add `reasoningEffort: String?` in Sources/Overtype/Config/AppConfig.swift: init defaults `nil`; tolerant decode with default `nil`; trim `reasoningEffort` and map blank to `nil`; synthesized encode omits `nil` keys
- [X] T005 Create Sources/Overtype/Providers/GenerationParameters.swift with `ReasoningSetting` (`level(String)`, `thinkingBudget(Int)`) and `DroppableParameter` (`temperature`, `reasoning`), per data-model.md
- [X] T006 Change `TransformRequest` in Sources/Overtype/Providers/AIProvider.swift: `temperature: Double?`, add `reasoning: ReasoningSetting? = nil` (existing call sites passing a `Double` keep compiling), and add `removing(_ parameter: DroppableParameter) -> TransformRequest?` returning `nil` when the request does not carry that parameter
- [X] T007 Make temperature optional in every provider while keeping today's behavior for a set value: extract static `requestBody(model:systemPrompt:userPrompt:temperature:)` in Sources/Overtype/Providers/OpenAICompatibleProvider.swift and `requestBody(systemPrompt:userPrompt:temperature:)` in Sources/Overtype/Providers/GeminiProvider.swift (omit `generationConfig` when empty, research R9), and change `requestBody` in Sources/Overtype/Providers/OllamaProvider.swift to take `temperature: Double?` (send `options.temperature` only when set); update the `ActionEngine.run` call site in Sources/Overtype/Core/ActionEngine.swift to pass `action.temperature`
- [X] T008 Checkpoint: `make test` green (T002 and T003 pass); package builds with no warnings introduced

---

## Phase 3: User Story 1 - Current models work with no extra setup (Priority: P1) MVP

**Goal**: Profiled OpenAI, Anthropic and Gemini models get the right parameters with both settings on "Automatic"; unprofiled models get exactly today's request.

**Independent Test**: quickstart Q2 (existing config, model changed to `gpt-6-luna`, first request succeeds) plus the resolver and body-builder unit tests.

### Tests for User Story 1

- [X] T009 [P] [US1] Create Tests/OvertypeTests/ModelProfilesTests.swift: exact ID match; `-YYYY-MM-DD` and `-YYYYMMDD` snapshot match (`claude-opus-4-5-20251101` uses the `claude-opus-4-5` profile); no match for `gpt-6-luna-mini` or `gemini-3-flash-preview-x`; a profile of one kind never matches another kind; every table row from contracts/model-profiles.md is present with the listed values, preferred value and temperature rule; preferred value is always within the supported values
- [X] T010 [P] [US1] Create Tests/OvertypeTests/GenerationParameterResolverTests.swift: Automatic uses the profile's preferred value (`gpt-6-luna` → `.level("none")`, `claude-haiku-5-5` → `.level("low")`, `gemini-3.8-flash` → `.level("low")`, `gemini-2.5-flash` → `.thinkingBudget(0)`); an override wins over the preference; Luna keeps temperature at `none` and withholds it at an override of `medium` (reason `modelRejects`); Gemini 3.x and 4 withhold any temperature (reason `providerSaysRemove`); an unsupported override value is withheld (`unsupportedValue`), including a text override on a `thinkingBudget` model; an unprofiled model passes overrides through unchanged; Anthropic never yields a temperature; Ollama never yields reasoning (`providerIgnores`); `automaticReasoning` reports the caption value; also cover `TransformRequest.removing(_:)` for both parameters
- [X] T011 [P] [US1] Add body-builder tests to Tests/OvertypeTests/OpenAICompatibleProviderTests.swift: `reasoning_effort` present for `.level`, absent for `nil`; `temperature` present only when set; no other keys beyond `model` and `messages`
- [X] T012 [P] [US1] Add tests to Tests/OvertypeTests/AnthropicProviderTests.swift: `output_config.effort` present for `.level`, `output_config` absent for `nil`; `temperature` still absent; no `thinking` key
- [X] T013 [P] [US1] Add tests to Tests/OvertypeTests/GeminiProviderTests.swift: `thinkingConfig.thinkingLevel` for `.level`, `thinkingConfig.thinkingBudget` for `.thinkingBudget`, never both; `temperature` only when set; `generationConfig` omitted when both are `nil`

### Implementation for User Story 1

- [X] T014 [US1] Create Sources/Overtype/Providers/ModelProfiles.swift: `ModelProfile`, `ReasoningSpec` (parameter form, supported values or budget range, preferred value), `TemperatureRule` (`accepted`, `acceptedOnlyAtLevels`, `omitted`), the full table from contracts/model-profiles.md with a source-and-date note per provider block, `profile(for kind: ProviderKind, model: String)` with the snapshot rule from research R5, and the per-kind dictionaries for editor reasoning values and kinds that take a reasoning setting (dictionaries only, no exhaustive `switch` over `ProviderKind`, research R8)
- [X] T015 [US1] Implement `ResolvedGenerationParameters` and the pure `GenerationParameterResolver.resolve(kind:model:temperatureOverride:reasoningOverride:learnedRejections:)` in Sources/Overtype/Providers/GenerationParameters.swift, following the resolution order in data-model.md; comment each withholding rule with its reason and source (FR-026)
- [X] T016 [P] [US1] Add `reasoning` to `OpenAICompatibleProvider.requestBody` (`reasoning_effort` for `.level`, ignore `.thinkingBudget`) in Sources/Overtype/Providers/OpenAICompatibleProvider.swift
- [X] T017 [P] [US1] Add `effort: String?` to `AnthropicProvider.requestBody` (emit `output_config.effort` when set) and rewrite the DELIBERATE OMISSION comment: temperature is still never sent, effort is now sent for profiled models, `thinking` stays unsent, in Sources/Overtype/Providers/AnthropicProvider.swift
- [X] T018 [P] [US1] Add `reasoning` to `GeminiProvider.requestBody` (`thinkingLevel` or `thinkingBudget` inside `thinkingConfig`) with a comment citing the 400 for both together, in Sources/Overtype/Providers/GeminiProvider.swift
- [X] T019 [US1] In `ActionEngine.run` (Sources/Overtype/Core/ActionEngine.swift), resolve parameters from the provider kind, the resolved model, `action.temperature`, `action.reasoningEffort` and an empty learned set, then build `TransformRequest` with the resolved `temperature` and `reasoning`; pass the request's reasoning to each provider's builder from its `transform` method
- [X] T020 [US1] Checkpoint: `make test` green; SC-004 holds in tests (an unprofiled model with an override set produces the same body as before this feature)

---

## Phase 4: User Story 2 - New users start on a current OpenAI model (Priority: P1)

**Goal**: Fresh installs and new OpenAI providers default to `gpt-6-luna`; existing configurations keep their model.

**Independent Test**: quickstart Q3 and Q6 step 5, plus the seeded-config unit assertion.

### Tests for User Story 2

- [X] T021 [P] [US2] Add to Tests/OvertypeTests/AppConfigTests.swift: the seeded `DefaultConfig.defaultConfig` decodes with the OpenAI provider's `defaultModel` equal to `gpt-6-luna` and its action's `temperature` and `reasoningEffort` both `nil`; the suggested default model for the OpenAI kind is `gpt-6-luna` and other kinds have none
- [X] T022 [P] [US2] Add to Tests/OvertypeTests/ConfigStoreTests.swift: decoding an existing configuration whose OpenAI provider has `defaultModel` `gpt-5.4-nano` and whose action stores `"temperature": 0` keeps both values unchanged, through the same decoder setup `ConfigStore` uses (seeding happens only when no file exists; FR-019)

### Implementation for User Story 2

- [X] T023 [US2] Change the seeded JSON in Sources/Overtype/Config/DefaultConfig.swift: `"defaultModel": "gpt-6-luna"` and remove `"temperature"` from the `fix-grammar` action
- [X] T024 [US2] Add the suggested-default-model dictionary (`openAICompatible` → `gpt-6-luna`) to Sources/Overtype/Providers/ModelProfiles.swift (file from T014)
- [X] T025 [US2] Pre-fill the default model in Sources/Overtype/UI/Settings/ProvidersTab.swift: `prepareAddForm` sets it from the suggestion for the initial kind; on a kind change while adding, replace the field only when it is empty or still holds the previous kind's suggestion; editing an existing provider never changes it
- [X] T026 [P] [US2] Replace `gpt-4o-mini` with `gpt-6-luna` in docs/openai-setup.md, and update the seeded config sample in README.md (`gpt-6-luna`, no `temperature` key)
- [X] T027 [US2] Checkpoint: `make test` green

---

## Phase 5: User Story 3 - Unknown OpenAI models adapt instead of failing (Priority: P1)

**Goal**: An OpenAI 400 that names `temperature` or `reasoning_effort` triggers one retry without it, remembered for the session; nothing changes for other errors or other providers.

**Independent Test**: quickstart Q4, plus the `TransformRetryTests` fallback cases.

### Tests for User Story 3

- [X] T028 [P] [US3] Add to Tests/OvertypeTests/OpenAICompatibleProviderTests.swift: `extractRejectedParameter(from:)` maps `error.param` `temperature` → `.temperature` and `reasoning_effort` → `.reasoning`; any other `param`, a missing `param`, and a non-JSON body give `nil`
- [X] T029 [P] [US3] Add to Tests/OvertypeTests/ProviderErrorRetryTests.swift and Tests/OvertypeTests/ProviderErrorMessageTests.swift: `parameterRejected` is not retryable; its `errorDescription` reads "API Error 400: <message>"; its `logLabel` names the parameter and never contains the message
- [X] T030 [P] [US3] Add fallback cases to Tests/OvertypeTests/TransformRetryTests.swift using the existing fake provider: one rejection then success sends two requests, the second without the parameter, and records it once; a second, different rejection is also dropped; the same parameter rejected again surfaces as `apiError(400, message)`; a rejection for a parameter the request does not carry surfaces as `apiError`; Escape during a drop sends no further request; a transient failure plus two drops never exceeds four requests; existing tests compile unchanged
- [X] T031 [P] [US3] Add `ParameterRejectionMemory` tests to Tests/OvertypeTests/GenerationParameterResolverTests.swift: entries are isolated per provider id, base URL and model; a recorded parameter is returned for the same key only; the resolver withholds a learned parameter with reason `learnedRejection`

### Implementation for User Story 3

- [X] T032 [US3] Add `ProviderError.parameterRejected(DroppableParameter, statusCode: Int, message: String)` with branches in `errorDescription`, `isRetryable` (false) and `logLabel` in Sources/Overtype/Providers/AIProvider.swift
- [X] T033 [US3] In Sources/Overtype/Providers/OpenAICompatibleProvider.swift, add static `extractRejectedParameter(from:)` reading `error.param` only (never the message, FR-016) and throw `parameterRejected` on a 400 that names a droppable parameter; every other non-200 keeps throwing `apiError`
- [X] T034 [US3] Add `ParameterRejectionMemory` (lock-protected, keyed by provider id, base URL string and model, shared instance) to Sources/Overtype/Providers/GenerationParameters.swift
- [X] T035 [US3] Extend `ActionEngine.transformWithRetry` in Sources/Overtype/Core/ActionEngine.swift with a defaulted `recordRejection: (DroppableParameter) -> Void` parameter and the drop loop from contracts/request-parameters.md (check cancellation, record, `warning` log with parameter name only, "Retrying...", no pause, rethrow undroppable rejections as `apiError`), keeping the single transient retry unchanged
- [X] T036 [US3] In `ActionEngine.run`, read learned rejections for the provider, base URL and model before resolving, and pass a `recordRejection` closure that writes to `ParameterRejectionMemory.shared`
- [X] T037 [US3] Checkpoint: `make test` green

---

## Phase 6: User Story 4 - Advanced users can override the automatic choice (Priority: P2)

**Goal**: The Actions editor offers "Automatic" or a value for both settings, shows what Automatic means for the selected model, and warns when an override will not be sent.

**Independent Test**: quickstart Q6 steps 1 to 4.

### Tests for User Story 4

- [X] T038 [P] [US4] Create Tests/OvertypeTests/ActionParameterValidationTests.swift for a new pure static `SettingsViewModel.normalizedGenerationOverrides(temperature:reasoningEffort:)`: `nil` temperature passes; 0.0 and 2.0 pass; -0.1 and 2.1 throw the existing code-13 error; the effort is trimmed and blank becomes `nil`; a hand-edited value outside the editor list is kept (FR-020 to FR-022)

### Implementation for User Story 4

- [X] T039 [US4] Add `normalizedGenerationOverrides(temperature:reasoningEffort:)` (pure, static) and change `SettingsViewModel.saveAction` in Sources/Overtype/UI/Settings/SettingsViewModel.swift to take `temperature: Double?` and `reasoningEffort: String?` and call it: the 0.0 to 2.0 check applies only when a temperature is set; the effort is trimmed and blank is stored as `nil`
- [X] T040 [US4] Update Sources/Overtype/UI/Settings/ActionsTab.swift: temperature as an "Automatic" toggle plus the existing slider; a reasoning picker with "Automatic (<resolved>)", the provider kind's values, and a preserved hand-edited value; the picker hidden for kinds that take no reasoning setting, with a note that reasoning effort applies only to the providers that list values; new actions start on Automatic for both; load existing values when editing
- [X] T041 [US4] In Sources/Overtype/UI/Settings/ActionsTab.swift, call `GenerationParameterResolver.resolve` for the selected provider kind and model (action override, else provider default) to fill the Automatic caption and show one warning line per entry in `withheldOverrides`
- [ ] T042 [US4] Checkpoint: `make test` green; run quickstart Q6

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T043 [P] Update README.md: "Specifying the AI Model" explains Automatic, both overrides and the OpenAI fallback; the Anthropic recipe uses `claude-haiku-5-5` and its two temperature notes are rewritten (research R3); the Ollama note keeps "temperature is sent when set"; the Gemini recipe stays on `gemini-3.5-flash-lite`
- [X] T044 [P] Update CLAUDE.md: model profiles and the resolver, the OpenAI-only fallback and its four-request bound, the optional `temperature` and new `reasoningEffort` action fields, and the new OpenAI default model
- [X] T045 Review every omission and withholding site for an inline reason comment (FR-026) in Sources/Overtype/Providers/ and Sources/Overtype/Core/ActionEngine.swift
- [X] T046 Run `make test`, `make lint` and `rg NSPasteboard Sources/ Vendor/`; confirm no `info`+ log line contains a server message or selected text
- [X] T047 Manual, needs the user's API keys: run quickstart Q1 (diagnostic) and adjust the `gpt-6-luna` and `gpt-6-sol` profiles in Sources/Overtype/Providers/ModelProfiles.swift if the temperature-at-`none` inference is wrong
- [ ] T048 Manual, needs the user's API keys: run quickstart Q2 to Q5; for SC-005 also confirm one first-request success with both settings on Automatic for each profile shape (`gpt-6-luna`, `gpt-6.1-sol`, `claude-haiku-5-5`, `gemini-3.5-flash-lite`, `gemini-3.8-flash`, `gemini-2.5-flash`); record Q1 to Q6 and these runs in docs/compatibility.md

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002 to T008)** → user stories.
- **US1 (T009 to T020)**: depends on Foundational only. MVP.
- **US2 (T021 to T027)**: depends on Foundational; T024 needs `ModelProfiles.swift` from T014, so run US2 after T014 or create the file first.
- **US3 (T028 to T037)**: depends on Foundational and on T015 (the resolver takes learned rejections) and T019 (the engine call site).
- **US4 (T038 to T042)**: depends on US1 (resolver and profiles for the caption and warnings).
- **Polish (T043 to T048)**: after all stories. T047 should run before the release that ships the fallback.

### Parallel opportunities

- Foundational: T002 and T003.
- US1: T009 to T013 together (separate test files); T016, T017, T018 together after T015.
- US2: T021 and T022 together; T026 alongside T023 to T025.
- US3: T028 to T031 together.
- Polish: T043 and T044.

### Parallel example: User Story 1

```text
T009 ModelProfilesTests.swift
T010 GenerationParameterResolverTests.swift
T011 OpenAICompatibleProviderTests.swift
T012 AnthropicProviderTests.swift
T013 GeminiProviderTests.swift
```

## Implementation Strategy

1. **MVP**: Setup, Foundational, then US1. This alone fixes the reported `gpt-6-luna` error for every profiled model and makes Automatic fast; stop and validate with quickstart Q2.
2. **US2**: new default model, small and independent.
3. **US3**: the fallback for unprofiled OpenAI models; ship only after the T047 diagnostic, or ship inert if `error.param` turns out to be absent.
4. **US4**: editor controls.
5. **Polish**: docs, comment review, full checks, manual acceptance.

## Remediation: Gaps

- [X] T049 Update the `TemperatureRule` cases in the ModelProfile entity to `accepted`, `acceptedOnlyAtLevels`, `rejected` and `discouraged` (replacing `omitted`) in specs/010-model-aware-parameters/data-model.md [Sync: review-fixes-pass-2]
- [X] T050 Update the ParameterRejectionMemory entity to store the rejected value per parameter (`record(_:value:for:)`, `learnedRejections(for:matching:)`, `wireValue`) and describe `GenerationParameterResolver.resolve(...memory:key:)` in specs/010-model-aware-parameters/data-model.md [Sync: review-fixes-pass-2]
- [X] T051 Update the OpenAI error classification and "Adaptive fallback" rules to drop only plausible values (temperature 0.0 to 2.0, or a reasoning level from the OpenAI value list) and to remember the rejected value in specs/010-model-aware-parameters/contracts/request-parameters.md [Sync: review-fixes-pass-2]
