# Implementation Plan: Model-Aware Generation Parameters

**Branch**: `010-model-aware-parameters` | **Date**: 2026-10-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-model-aware-parameters/spec.md`

## Summary

Overtype stops pushing model details onto the user. Today every request carries the action's `temperature`, which current OpenAI reasoning models reject (the reported `gpt-6-luna` 400), and no request sets a reasoning level, so every reasoning model thinks at its slow default while the user waits.

The approach, from the spec's clarifications and research:

1. **Built-in model profiles** for OpenAI, Anthropic and Gemini (`contracts/model-profiles.md`): per model, the provider-native reasoning parameter and its values, the temperature rule, and the fastest supported reasoning value as Overtype's preference.
2. **One pure resolver** turns (provider kind, model, action overrides, learned rejections) into the parameters to send, plus the overrides it withheld and why. `ActionEngine.run` and the Actions editor both call it, so the editor's "Automatic (none)" caption and warnings always match the real request.
3. **Optional action fields**: `temperature` becomes optional and `reasoningEffort` is added; absent means "Automatic".
4. **Adaptive fallback, OpenAI only**: a 400 whose `error.param` names `temperature` or `reasoning_effort` makes the engine retry once without it and remember that for the session.
5. **New default model**: `gpt-6-luna` for the seeded OpenAI provider and for new OpenAI providers in Settings.

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+

**Primary Dependencies**: `URLSession` (async/await), SwiftUI, existing `ConfigStore`, `ProviderRegistry`, `ActionEngine`, `KeyboardShortcuts` (vendored, untouched). No new dependency.

**Storage**: `config.json` (action gains one optional key, `temperature` becomes optional; see `data-model.md`). Learned rejections are in memory only.

**Testing**: XCTest via `make test` for all pure logic (FR-025): profile matching, resolver, every provider's body builder, OpenAI error classification, the fallback loop in `transformWithRetry`, config decode and encode. Manual acceptance per `quickstart.md`, recorded in `docs/compatibility.md`.

**Target Platform**: macOS 13 or later, menu bar accessory.

**Project Type**: Desktop app (single Swift package).

**Performance Goals**: "Automatic" should lower the median run time on profiled reasoning models (SC-005). The resolver is a dictionary lookup and adds no measurable time.

**Constraints**: No new network endpoint; at most four requests per run; no selected text or server message in `info`+ logs; Principle IV three-edit rule for new providers preserved.

**Scale/Scope**: About 30 profiles across three providers; 4 provider files, 2 new source files, 6 edited source files, about 8 test files, 4 docs.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | How this plan satisfies it |
|---|---|
| I. Clipboard Isolation | No clipboard involvement; only request bodies and settings change. |
| II. Non-Destructive | The adaptive retry happens inside the provider call, before the context re-check and the write; a failed or retried call changes nothing in the document. |
| III. Evidence Over Assumption | Every profile cites its source and date; inferred facts (Luna temperature at `none`) are marked and confirmed by quickstart Q1/Q2; the fallback relies on `error.param` only after the Q1 diagnostic; each omission carries an inline reason comment (FR-026). |
| IV. Configuration Over Code | Automations stay declarative; the two new action fields are optional config keys editable in Settings. New code holds per-kind data in dictionaries keyed by `ProviderKind` (no new exhaustive `switch`), so adding a provider remains three edits and profiles stay optional for it (research R8). |
| V. Privacy | No new endpoint. Logs carry only the parameter name, provider id and model; the server message stays in the HUD and at debug level, as today. |
| VI. No Silent Failure | The new `ProviderError.parameterRejected` is a typed case; an undroppable rejection surfaces as today's "API Error 400" HUD; the retry shows "Retrying..." and is cancellable. |
| VII. Native Stack | Swift and SwiftUI only, no new dependency, no force unwrap. |
| VIII. Verification | All new logic is pure and unit-tested; provider behavior against live APIs is verified manually (quickstart Q1 to Q6) and recorded. |

Result: PASS. Post-design re-check: PASS (no design artifact introduced a violation).

## Design

### New files

- `Sources/Overtype/Providers/ModelProfiles.swift`: `ModelProfile`, `ReasoningSpec`, `TemperatureRule`, the built-in table (`contracts/model-profiles.md`), `profile(for:model:)` with the snapshot rule (research R5), and three per-kind dictionaries: editor reasoning values, suggested default model, and which kinds take a reasoning setting.
- `Sources/Overtype/Providers/GenerationParameters.swift`: `ReasoningSetting`, `DroppableParameter`, `ResolvedGenerationParameters`, the pure resolver `GenerationParameterResolver.resolve(kind:model:temperatureOverride:reasoningOverride:learnedRejections:)` plus `resolve(...memory:key:)`, which applies a learned rejection only when this run would send the same value and is used by both `ActionEngine.run` and the Actions editor, and `ParameterRejectionMemory` (lock-protected, research R7), which records the rejected value per parameter (`record(_:value:for:)`, `learnedRejections(for:matching:)`, `wireValue`) so a changed value is sent again; the "Automatic" caption is empty once that automatic value was rejected.

### Changed files

- `Providers/AIProvider.swift`: `TransformRequest.temperature` becomes `Double?`; add `reasoning: ReasoningSetting? = nil` and `removing(_:)`; add `ProviderError.parameterRejected` with branches in `errorDescription`, `isRetryable` (false) and `logLabel`.
- `Providers/OpenAICompatibleProvider.swift`: static `requestBody(model:systemPrompt:userPrompt:temperature:reasoning:)`; static `extractRejectedParameter(from:)` reading `error.param`; static `isPlausibleValue(of:in:)` (temperature 0.0 to 2.0, or a reasoning level from the OpenAI value list); throw `parameterRejected` on a 400 that names a droppable parameter whose sent value is plausible, and `apiError` otherwise, so a typo keeps its 400.
- `Providers/AnthropicProvider.swift`: `requestBody` gains `effort: String?` and emits `output_config` when set; the omission comment is updated (temperature still never sent; effort now sent for profiled models).
- `Providers/GeminiProvider.swift`: extract static `requestBody(systemPrompt:userPrompt:temperature:reasoning:)`; `generationConfig` omitted when empty (research R9).
- `Providers/OllamaProvider.swift`: `requestBody` takes `temperature: Double?`; `options.temperature` only when set.
- `Core/ActionEngine.swift`: resolve parameters before building the request (profile + overrides + learned rejections, through `resolve(...memory:key:)`); log each withheld override at `warning` with parameter, reason and model, never the value (FR-028); record a drop with the value the run started with; `transformWithRetry` gains a defaulted `recordRejection` closure and the drop loop (`contracts/request-parameters.md`, "Adaptive fallback").
- `Config/AppConfig.swift`: `ActionConfig.temperature: Double?`, new `reasoningEffort: String?`, tolerant decode with blank-to-nil, init defaults `nil`.
- `Config/DefaultConfig.swift`: `defaultModel` `gpt-6-luna`; seeded action without `temperature`.
- `UI/Settings/SettingsViewModel.swift`: `saveAction` takes `temperature: Double?` and `reasoningEffort: String?`; range check only when set.
- `UI/Settings/ActionsTab.swift`: "Automatic" toggle plus slider for temperature; reasoning picker with "Automatic (<resolved>)", the kind's values, and a preserved custom value; warning text from `withheldOverrides`; picker hidden for kinds that take no reasoning setting, and for those kinds the reasoning value is neither resolved nor saved (`reasoningOverrideToSave`), so nothing invisible is stored.
- `UI/Settings/ProvidersTab.swift`: pre-fill `defaultModel` from the suggested-model dictionary when adding a provider, and when the kind changes while the field still holds the previous suggestion or is empty.

### Tests

New: `ModelProfilesTests` (exact match, both dated-snapshot forms, no match for `gpt-6-luna-mini`, kind isolation), `GenerationParameterResolverTests` (Automatic uses preferred; override wins; Luna temperature withheld at `medium`; Gemini 3.x temperature withheld; unsupported value withheld; unknown model passes overrides through; Anthropic temperature never; Ollama reasoning never; learned rejections removed; withheld reasons; value-keyed rejection memory), and `ActionParameterValidationTests` (the editor's pure `SettingsViewModel.normalizedGenerationOverrides`).

Changed, intentionally:
- `AppConfigTests`: missing `temperature` now decodes to `nil` (was `0.0`, line 159); wrong-typed now `nil` plus an issue (was `0.0`, line 232); new cases for `reasoningEffort` blank-to-nil and wrong type; encode omits both keys when nil; an old config with `"temperature": 0` keeps `0`.
- `OllamaProviderTests`: the exact `options` key set stays `["temperature", "num_ctx"]` with a temperature, and a new case asserts `["num_ctx"]` without one.
- `AnthropicProviderTests`: still asserts no `temperature`; new cases for `output_config` present and absent.
- `ConfigStoreTests`: an existing configuration keeps its `defaultModel` and stored temperature through the decode `ConfigStore` uses (FR-019).
- `OpenAICompatibleProviderTests`, `GeminiProviderTests`: body builder cases per contract; OpenAI error-param classification.
- `TransformRetryTests`: existing tests compile unchanged (new parameters are defaulted); new cases for one drop and success, drop recorded, a second different drop, the same parameter rejected twice surfacing as `apiError`, cancellation during a drop, and the four-request bound with a transient failure mixed in.
- `ProviderErrorRetryTests`, `ProviderErrorMessageTests`: the new case is not retryable and its label carries no message.
- A `DefaultConfig` assertion: seeded model `gpt-6-luna`, no temperature on the seeded action.

### Documentation

- `README.md`: seeded config sample (`gpt-6-luna`, no temperature); "Specifying the AI Model" gains "Automatic" and the overrides; Anthropic recipe moves to `claude-haiku-5-5` and its temperature notes are rewritten (research R3); Ollama note keeps "temperature is sent when set"; one paragraph on the OpenAI fallback.
- `docs/openai-setup.md`: `gpt-4o-mini` becomes `gpt-6-luna`.
- `CLAUDE.md`: architecture notes for profiles, the resolver, the fallback, and the optional action fields.
- `docs/compatibility.md`: quickstart Q1 to Q6 results.
- Untouched on purpose: `docs/privacy.md` (no new endpoint or data), `Support/Overtype/config.json` (stale sample, already tracked as a known deviation).

## Project Structure

### Documentation (this feature)

```text
specs/010-model-aware-parameters/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── request-parameters.md
│   └── model-profiles.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks output
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Config/        AppConfig.swift, DefaultConfig.swift
├── Core/          ActionEngine.swift
├── Providers/     AIProvider.swift, OpenAICompatibleProvider.swift, AnthropicProvider.swift,
│                  GeminiProvider.swift, OllamaProvider.swift,
│                  ModelProfiles.swift (new), GenerationParameters.swift (new)
└── UI/Settings/   ActionsTab.swift, ProvidersTab.swift, SettingsViewModel.swift

Tests/OvertypeTests/
├── ModelProfilesTests.swift (new), GenerationParameterResolverTests.swift (new),
│   ActionParameterValidationTests.swift (new), ConfigStoreTests.swift
└── AppConfigTests, OllamaProviderTests, AnthropicProviderTests, OpenAICompatibleProviderTests,
    GeminiProviderTests, TransformRetryTests, ProviderErrorRetryTests, ProviderErrorMessageTests
```

**Structure Decision**: Single Swift package, existing layout. The two new files sit in `Providers/` beside the code that consumes them.

## Complexity Tracking

| Choice | Why needed | Simpler alternative rejected because |
|---|---|---|
| A built-in per-model table (reverses feature 007's "no list") | The user requires the project, not the end user, to know model rules (spec Clarifications) | Never sending optional parameters cannot pick a fast reasoning level, and sending them blindly breaks models that reject them. |
| A second retry kind in `transformWithRetry` | Unprofiled OpenAI models must not fail on a parameter Overtype could drop | Retrying inside the provider cannot show HUD progress and would hide a retry policy from the tested seam. |

## Merge exception 2026-10-17

- The feature was merged to `main` with quickstart Q3 to Q6 (tasks T042 and T048) still recorded as pending in `docs/compatibility.md`. Q1 (the OpenAI diagnostic, T047) and Q2 (SC-001, the reported `gpt-6-luna` case, end to end) passed. This is an explicit, dated exception to constitution Principle VIII, approved by the project owner on 2026-10-17. It covers the merge only: no release may ship until Q3 to Q6 pass, and any regression they reveal is a release blocker for the next tag.

## Revisions

### Revision: Implementation Sync 2026-10-17 [Sync: review-fixes-pass-2]
- Reason: Recorded the accepted multi-model review fixes (commit 333496b) in the design and test lists: plausible-value gate in the OpenAI provider, value-keyed rejection memory and the shared `resolve(...memory:key:)`, run-time logging of withheld overrides, the editor no longer saving a hidden reasoning value, and the two test files the plan did not list.
- Items: Design → "`Sources/Overtype/Providers/GenerationParameters.swift`"; Design → "`Providers/OpenAICompatibleProvider.swift`"; Design → "`Core/ActionEngine.swift`"; Design → "`UI/Settings/ActionsTab.swift`"; Tests → "New:"; Tests → "`ConfigStoreTests`" (new); Project Structure → test tree
- Approved: approve all
