# Implementation Plan: Apple Foundation Models Provider

**Branch**: `011-apple-foundation-models` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-apple-foundation-models/spec.md`

## Summary

Add a fifth provider kind, `apple`, that runs Overtype actions on Apple's on-device model through the public `FoundationModels` framework (macOS 27+, gated at run time). Each run checks model availability, opens a fresh `LanguageModelSession` with the permissive-transformations guardrails, sends the system prompt as instructions and the rendered prompt as the request, races generation against the provider timeout, and maps every framework failure to a typed `ProviderError`. The model profile is measured, not assumed: the on-device model accepts any temperature and rejects every reasoning level. Settings hide the address and key fields for this kind. CI and release move to the `xcode-27` runner so the shipped app contains the provider.

## Technical Context

**Language/Version**: Swift 5.9 language mode, built with Xcode 27.2 (Swift 6.4.2)

**Primary Dependencies**: `FoundationModels` (system framework, macOS 27 API, weak-linked); existing `KeyboardShortcuts` (vendored, unchanged)

**Storage**: `config.json` (one new kind value); no Keychain use for this kind

**Testing**: XCTest via `swift test`; framework-error mapping tests construct real `LanguageModelError` values and skip on macOS < 27

**Target Platform**: macOS 13+ app; Apple provider functional on macOS 27+ with Apple Intelligence

**Project Type**: Native macOS menu bar app (SwiftPM)

**Performance Goals**: 300-character grammar fix under 3 s end to end (measured model latency about 0.25 s)

**Constraints**: No network, no subprocess, no clipboard; 8,192-token context window; hard timeout per request

**Scale/Scope**: 1 new provider file, edits in 6 source files, 1 new test file plus additions to 4, 2 workflow files, 4 docs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design: still passes.*

| Principle | How the plan satisfies it |
|---|---|
| I. Clipboard Isolation | The provider touches only the model API. Reading and writing stay in the unchanged pipeline. PR check `rg NSPasteboard Sources/ Vendor/` stays clean. |
| II. Non-Destructive | The provider returns text or throws; the write and context re-check in `ActionEngine` are unchanged. No `maximumResponseTokens`, because a capped response is silently truncated (research R7), which would replace the whole selection with part of it. |
| III. Evidence Over Assumption | Profile values, context size, truncation, cancellation and language behaviour come from diagnostic runs (research R6 to R11), recorded in `docs/compatibility.md`. The background-app rate-limit question stays open until quickstart Q4 runs the real app. The guardrail choice carries an inline comment. |
| IV. Configuration Over Code | Backend added with the three edits: `ProviderKind.apple`, `AppleFoundationModelProvider`, one `ProviderRegistry` line. Actions need no code. Three further files change; each is recorded as an explicit, dated exception (E1 to E3 under Complexity Tracking), as the Governance clause requires. |
| V. Privacy | No network, no key, no logging of text (only `logLabel`). The provider list shows "On this Mac (no network)" so the user sees where text goes. `docs/privacy.md` updated. |
| VI. No Silent Failure | Every unavailability reason and framework error has a specific typed message (data-model.md). Cancellable through structured concurrency (measured 0.32 s). Hard timeout through a task-group race. |
| VII. Native Stack | System framework only, no new package. No force unwrap. Swift 5.9 mode kept. The app stays macOS 13+; the framework is weak-linked (verified by spike, re-verified on the built app). |
| VIII. Verification | Pure mapping, messages, retryability, profile and settings logic are unit-tested. The model call is system-boundary code, covered by quickstart Q1 to Q9 in `docs/compatibility.md`. |
| Platform constraints | Build now requires Xcode 27; CI and release use the `xcode-27` preview runner (user decision, research R2), pinned to `/Applications/Xcode_27.2.app`, the toolchain the provider was verified with, because `/Applications/Xcode.app` on that image is Xcode 27.1. |

Passes with the three dated exceptions E1 to E3 below.

## Project Structure

### Documentation (this feature)

```text
specs/011-apple-foundation-models/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/apple-provider.md
└── tasks.md            # created by /speckit-tasks
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Config/AppConfig.swift                    # + case apple = "apple"
├── Providers/
│   ├── AppleFoundationModelProvider.swift    # NEW: provider, availability + error mapping, timeout race
│   ├── AIProvider.swift                      # + 5 ProviderError cases, OnDeviceModelUnavailability
│   ├── ModelProfiles.swift                   # + apple profile row, suggested model, kinds without endpoint/key
│   └── ProviderRegistry.swift                # + one line
└── UI/Settings/
    ├── ProvidersTab.swift                    # label, hidden URL/key fields, list row text
    └── SettingsViewModel.swift               # apple saves no URL/key, deletes stale key

Tests/OvertypeTests/
├── AppleFoundationModelProviderTests.swift   # NEW: availability + error mapping (macOS 27, real values)
├── ProviderErrorMessageTests.swift           # + messages for new cases
├── ProviderErrorRetryTests.swift             # + retryability for new cases
├── ModelProfilesTests.swift                  # + apple row, resolver output for apple
└── SettingsReloadTests.swift (or a new SettingsProviderSaveTests.swift)  # apple save drops URL/key

.github/workflows/ci.yml, release.yml          # runs-on: xcode-27
README.md, docs/privacy.md, docs/compatibility.md, CLAUDE.md
```

**Structure Decision**: Single SwiftPM executable target, existing layout. The provider lives in one file next to the other providers.

## Design Notes

- **Availability gate**: `transform` starts with `guard #available(macOS 27, *) else { throw ProviderError.onDeviceModelUnavailable(.operatingSystemTooOld) }`, then calls a `@available(macOS 27, *)` private implementation. Nothing from `FoundationModels` is stored in properties, so the class itself has no availability attribute and `ProviderRegistry` can create it on any OS.
- **Model check**: a model other than empty or `system` throws `.modelNotAvailable(model:)` (research R13).
- **Generation**: `LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations), instructions: request.systemPrompt)`, then `respond(to: prompt, options: GenerationOptions(temperature: request.temperature))`. Blank content throws `.emptyResponse`.
- **Timeout**: throwing task group of the generation and `Task.sleep(timeoutSeconds)`; first to finish wins, `cancelAll()` on the rest.
- **Retry**: `.rateLimited` and `.timeout` get the existing single retry; everything new is permanent (data-model.md).
- **Settings rule**: one `Set<ProviderKind>` (`ModelProfiles.kindsWithoutEndpointOrKey = [.apple]`) drives both the form (hide fields) and `saveProvider` (store nil, delete stale key, skip the Base URL check for the hidden field), so the two cannot disagree. `ProvidersTab.changeKind` sets the model to `system` when an existing provider switches to Apple with any other model (narrow exception to feature 010's FR-019, user decision 2026-11-19).
- **ActionEngine**: no change. Parameter resolution, retry and error display already handle the new kind and cases generically.

## Complexity Tracking

Explicit, dated exceptions to Principle IV ("No other file may need to change"), recorded 2026-11-19 under the Governance clause "Any deviation found MUST be either corrected or recorded as an explicit, dated exception in the plan that introduced it". Feature 008 recorded the same kind of exceptions (`specs/008-ollama-provider/plan.md`).

| ID | Exception (file) | Why needed | Simpler alternative rejected because |
|----|------------------|------------|-------------------------------------|
| E1 | Five new `ProviderError` cases in `Providers/AIProvider.swift` | Principle VI requires typed errors that tell the user what failed and what to do; on-device unavailability, token context limit, unsupported language, rate limit and generic model failure have no existing case with a correct message | Reusing existing cases moves the cause into a string (forbidden by Principle VI) or shows a wrong message (`inputTooLargeForContext` counts bytes, `apiError(429)` says "API Error") |
| E2 | Apple branch in `UI/Settings/ProvidersTab.swift` and `UI/Settings/SettingsViewModel.swift` | FR-012: the form must not ask for an address or key, and saving must store neither and delete a stale key | Without it, the form offers fields the provider ignores and the create path always writes a `keychainKey` reference, contradicting User Story 2 scenario 2 |
| E3 | Profile row and per-kind data in `Providers/ModelProfiles.swift` | FR-011 and the 010 rule: every kind's parameters come from the shared resolver and its profile table | Without a profile the editor shows no evidence-based Automatic caption, and the suggested model `system` would not be pre-filled |

## Revisions

### Revision: Implementation Sync 2026-11-19 [Sync: apple-settings-and-ci-pin]
- Reason: Implementation pass 2 recorded the Apple Settings decisions (model set to `system` on switch, hidden Base URL not validated) and pinned CI and release to Xcode 27.2.
- Items: Design Notes "Settings rule", Constitution Check "Platform constraints"
- Approved: approve all
