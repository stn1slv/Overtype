# Tasks: Apple Foundation Models Provider

**Input**: Design documents from `specs/011-apple-foundation-models/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/apple-provider.md, quickstart.md

**Tests**: Included. Constitution Principle VIII requires unit tests for new pure logic (error mapping, messages, retryability, profiles, settings rule). The model call itself is system-boundary code, verified by the manual acceptance in quickstart.md.

**Build note**: every build and test command needs Xcode 27: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story the task belongs to (US1 to US4)

---

## Phase 1: Setup

**Purpose**: Make CI and release able to compile the macOS 27 API (research R2).

- [ ] T001 [P] Change `runs-on: macos-latest` to `runs-on: xcode-27` in .github/workflows/ci.yml, and add a comment that the `FoundationModels` macOS 27 API needs Xcode 27 (specs/011 research R2)
- [ ] T002 [P] Change every `runs-on: macos-latest` to `runs-on: xcode-27` in .github/workflows/release.yml, with the same comment, so the released app contains the Apple provider

---

## Phase 2: Foundational (blocks all user stories)

**Purpose**: The new kind and the shared error cases that every story uses.

- [ ] T003 Add `case apple = "apple"` to `ProviderKind` in Sources/Overtype/Config/AppConfig.swift (edit 1 of the three-edit rule)
- [ ] T004 Add `public enum OnDeviceModelUnavailability: Equatable { case operatingSystemTooOld, deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady, unknown }` and the five new `ProviderError` cases `onDeviceModelUnavailable(OnDeviceModelUnavailability)`, `contextWindowExceeded(tokenLimit: Int)`, `unsupportedLanguage(code: String)`, `rateLimited`, `onDeviceModelFailed(message: String)` in Sources/Overtype/Providers/AIProvider.swift, with `errorDescription` texts exactly as in data-model.md (the `contextWindowExceeded` text must say the selection, the prompt and the answer must fit in N tokens, per research R7), `isRetryable` true only for `rateLimited`, and payload-free `logLabel` values from data-model.md
- [ ] T005 Fix every exhaustive `switch` over `ProviderKind` that no longer compiles after T003 (expected: `baseURLPlaceholder` and `kindLabel` in Sources/Overtype/UI/Settings/ProvidersTab.swift) with a minimal `.apple` branch; the real UI behaviour comes in US2. Run `swift build` to confirm no other switch is affected
- [ ] T006 [P] Add tests for the five new cases to Tests/OvertypeTests/ProviderErrorMessageTests.swift: each message is specific, ends with "Nothing was changed.", and `contextWindowExceeded(tokenLimit: 8192)` mentions 8192 and the answer
- [ ] T007 [P] Add tests to Tests/OvertypeTests/ProviderErrorRetryTests.swift: `rateLimited` is retryable; `onDeviceModelUnavailable` (all five reasons), `contextWindowExceeded`, `unsupportedLanguage`, `onDeviceModelFailed` are not; each `logLabel` carries no payload (does not contain the code, the limit, or the message)

**Checkpoint**: `swift test` passes; the new kind decodes from config.

---

## Phase 3: User Story 1 - Run an action against Apple's on-device model (P1) 🎯 MVP

**Goal**: A configured Apple provider transforms the selection on device, cancellable and time-bounded.

**Independent Test**: quickstart Q1, Q2, Q3 with a hand-edited `config.json` record (data-model.md example).

- [ ] T008 [US1] Create Sources/Overtype/Providers/AppleFoundationModelProvider.swift with `public final class AppleFoundationModelProvider: AIProvider` (stores `id` and `timeoutSeconds` from `ProviderConfig`, no `FoundationModels` types in stored properties). `transform` must: (1) `guard #available(macOS 27, *)` else throw `.onDeviceModelUnavailable(.operatingSystemTooOld)`; (2) throw `.modelNotAvailable(model:)` when `request.model != "system"` (research R13; define `static let systemModelID = "system"`); (3) create `SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)` with an inline comment explaining the guardrail choice (spec Clarifications, FR-013); (4) check `availability` and throw the mapped error for `.unavailable`; (5) build the prompt by replacing `{{text}}` in `request.userPromptTemplate` with `request.text`; (6) create a fresh `LanguageModelSession(model:instructions: request.systemPrompt)` and call `respond(to:options: GenerationOptions(temperature: request.temperature))`, never setting `maximumResponseTokens` (comment citing research R7: a cap truncates silently) and never sending a reasoning level (research R6); (7) race the call against `Task.sleep(timeoutSeconds)` in a throwing task group, throwing `.timeout` when the sleep wins and cancelling the other child; (8) throw `.emptyResponse` when the content is blank after trimming whitespace; (9) catch errors and rethrow `providerError(from:)`. No logging (research R14)
- [ ] T009 [US1] In the same file add `@available(macOS 27, *) static func error(for reason: SystemLanguageModel.Availability.UnavailableReason) -> ProviderError` and `@available(macOS 27, *) static func providerError(from error: Error) -> ProviderError` implementing the research R5 table exactly (`ProviderError` passes through unchanged; `CancellationError` becomes `.cancelled`; `@unknown default` and unlisted cases become `.unknown` / `.onDeviceModelFailed(message: error.localizedDescription)`)
- [ ] T010 [US1] Register the provider with one line `case .apple: providers[config.id] = AppleFoundationModelProvider(config: config)` in Sources/Overtype/Providers/ProviderRegistry.swift (edit 3 of the three-edit rule)
- [ ] T011 [P] [US1] Create Tests/OvertypeTests/AppleFoundationModelProviderTests.swift testing the non-OS parts that run everywhere: a request whose model is not `system` throws `.modelNotAvailable("other")` (on macOS < 27 it throws `.onDeviceModelUnavailable(.operatingSystemTooOld)` instead; assert the right one with `#available`)

**Checkpoint**: Quickstart Q1 to Q3 pass with a hand-edited provider record.

---

## Phase 4: User Story 2 - Add the Apple provider without a key or an address (P1)

**Goal**: Settings offer the Apple kind with no address or key fields and save a clean record.

**Independent Test**: quickstart Q8 and Q9; add the provider through Settings only, then run Q1.

- [ ] T012 [US2] Add `static let kindsWithoutEndpointOrKey: Set<ProviderKind> = [.apple]` and `suggestedDefaultModel[.apple] = "system"` (use `AppleFoundationModelProvider.systemModelID`) to Sources/Overtype/Providers/ModelProfiles.swift, with a doc comment that both the form and `saveProvider` read this set (plan Design Notes)
- [ ] T013 [US2] In Sources/Overtype/UI/Settings/SettingsViewModel.swift add a pure `static func storedEndpointAndKey(kind: ProviderKind, url: URL?, keychainKey: String?) -> (url: URL?, keychainKey: String?)` that returns `(nil, nil)` for kinds in `kindsWithoutEndpointOrKey` and the inputs otherwise; use it in both the edit and create paths of `saveProvider`. For those kinds: do not store a typed API key, and in edit mode delete the stored Keychain item when one exists (research R12)
- [ ] T014 [US2] In Sources/Overtype/UI/Settings/ProvidersTab.swift: add `.apple` to `selectableKinds`; make `kindLabel(.apple)` return "Apple on-device", or "Apple on-device (requires macOS 27)" when `#available(macOS 27, *)` fails; hide the Base URL and API Key fields when the kind is in `kindsWithoutEndpointOrKey` and show the caption "Runs on this Mac. No network, no API key." instead; in the provider list, show "On this Mac (no network)" for such kinds instead of "Default Endpoint" (Principle V)
- [ ] T015 [P] [US2] Add tests for `storedEndpointAndKey` to a new Tests/OvertypeTests/ProviderSettingsRuleTests.swift: `.apple` drops a URL and a key; `.ollama` and `.openAICompatible` keep both; plus a config decode test that `{"id":"apple","kind":"apple","defaultModel":"system","timeoutSeconds":60}` decodes with no load warnings

**Checkpoint**: Q8 and Q9 pass; a Settings-created Apple provider runs Q1.

---

## Phase 5: User Story 3 - Clear errors when the model cannot run (P1)

**Goal**: Each unavailability reason and framework failure shows its own message.

**Independent Test**: quickstart Q5 and Q6; unit tests for the paths that cannot be produced on demand.

- [ ] T016 [US3] Add to Tests/OvertypeTests/AppleFoundationModelProviderTests.swift, guarded with `guard #available(macOS 27, *) else { throw XCTSkip("needs macOS 27") }`: availability mapping for `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`; error mapping built from real public initializers for `LanguageModelError.contextSizeExceeded` (tokenLimit equals `contextSize`), `.rateLimited`, `.guardrailViolation` and `.refusal` (both `.responseBlocked`), `.unsupportedLanguageOrLocale` (code carried), `.timeout`, `.unsupportedCapability` (`.onDeviceModelFailed`), `SystemLanguageModel.Error.assetsUnavailable` (`.modelNotReady`), `CancellationError` (`.cancelled`), a `ProviderError` passed through unchanged, and an unrelated `NSError` (`.onDeviceModelFailed`)
- [ ] T017 [US3] Run `swift test --filter AppleFoundationModelProviderTests` and fix any mapping gap in Sources/Overtype/Providers/AppleFoundationModelProvider.swift

**Checkpoint**: All mapping tests pass on macOS 27; Q5 and Q6 pass.

---

## Phase 6: User Story 4 - Generation settings that fit the model (P2)

**Goal**: The editor and the request agree: temperature passes, reasoning never appears.

**Independent Test**: quickstart Q7.

- [ ] T018 [US4] Add the profile row `ModelProfile(kind: .apple, modelID: "system", reasoning: nil, temperature: .accepted, source: appleSource)` to Sources/Overtype/Providers/ModelProfiles.swift, with `appleSource` = "on-device diagnostic 2026-11-19, macOS 27.2.1, AFM 3 Core Advanced: any temperature accepted, every reasoning level rejected (unsupportedCapability)" and an EVIDENCE OVER DOCUMENTATION comment pointing to docs/compatibility.md; add no `reasoningValues` entry for `.apple`
- [ ] T019 [P] [US4] Add tests to Tests/OvertypeTests/ModelProfilesTests.swift and Tests/OvertypeTests/GenerationParameterResolverTests.swift: the `.apple`/`system` profile exists; `reasoningValues[.apple]` is nil; resolving `.apple` with temperature 0.3 and reasoning override "low" returns temperature 0.3, reasoning nil, automatic reasoning nil, and one withheld override `(.reasoning, .providerIgnores)`

**Checkpoint**: Q7 passes.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T020 [P] Add an "Apple on-device model" section to README.md (after Ollama): requirements (macOS 27, Apple Intelligence on, model downloaded), Settings steps and the data-model.md config example with a 60 s timeout (research R7: a 5,000-character selection took about 24 s), text never leaves the Mac, no reasoning setting, the supported-language list and the risk that other languages get English answers (research R11); also add the provider to the Features list and the `reasoningEffort` paragraph
- [ ] T021 [P] Update docs/privacy.md "Network Requests": the Apple provider makes no network request and runs on device; Private Cloud Compute is not used
- [ ] T022 [P] Update CLAUDE.md: provider list (`apple` implemented via `FoundationModels`, macOS 27 runtime gate, weak-linked), build needs Xcode 27 and CI uses the `xcode-27` runner, and the "Adding an AI provider" paragraph
- [ ] T023 Add an "Apple on-device model (FoundationModels)" subsection to docs/compatibility.md under Provider Acceptance with the 2026-11-19 diagnostic results from research R6, R7, R8, R10 and R11
- [ ] T024 Run `make lint` and `make test`; fix lint findings in changed files only
- [ ] T025 Build with ./scripts/build-app.sh and confirm `otool -l Overtype.app/Contents/MacOS/Overtype` shows `LC_LOAD_WEAK_DYLIB` for FoundationModels.framework (research R3); confirm `rg NSPasteboard Sources/ Vendor/` has no new match
- [ ] T026 Execute quickstart Q1 to Q9 against the real app and record the results, including the Q4 background rate-limit finding, in docs/compatibility.md

---

## Dependencies & Execution Order

- Phase 1 (T001, T002) is independent of the code and can run any time before the PR.
- Phase 2 blocks everything: T003 → T004 → T005; T006 and T007 after T004.
- US1 (T008 to T011) needs Phase 2. US2 needs T008's `systemModelID` (T012). US3 tests need T009. US4 needs T012's file edits done first (same file, ModelProfiles.swift).
- Polish: T020 to T023 after US1 to US4; T024 → T025 → T026 last.

## Parallel Opportunities

- T001 with T002; T006 with T007.
- T011, T015, T019 are separate test files.
- T020, T021, T022 are separate documents.

## Implementation Strategy

1. MVP: Phases 1 to 3 give a working provider from a hand-edited config (US1).
2. Add US2 (Settings) and US3 (error coverage tests) next; both are P1.
3. US4 adds the profile row and its tests.
4. Polish and the manual acceptance close the feature.
