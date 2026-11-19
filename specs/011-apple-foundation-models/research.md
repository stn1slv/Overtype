# Research: Apple Foundation Models Provider

All findings below come from the macOS 27.2 SDK interface (`FoundationModels.swiftinterface`, Xcode 27.2) and from two diagnostic runs against the real on-device model on 2026-11-19 (macOS 27.2.1, model "AFM 3 Core Advanced"). The diagnostic programs were throwaway scratch code; their results are recorded in `docs/compatibility.md` during implementation (task list).

## R1: Integration route

- **Decision**: Use the public `FoundationModels` framework in process: `SystemLanguageModel` plus a new `LanguageModelSession` per run.
- **Rationale**: It is Apple's documented API for apps. No subprocess, no output parsing, no local server, and no network.
- **Alternatives considered**: `fm respond` as a subprocess (the `fm` licence forbids programmatic access except as expressly permitted, and its output format is not a contract); `fm serve` plus the OpenAI-compatible provider (needs a server the user keeps running). Both rejected by the user before the spec.

## R2: Minimum OS and compile strategy

- **Decision**: The provider runs on macOS 27+, gated at run time with `#available(macOS 27, *)`. No compile-time guard: the project requires Xcode 27 to build. `ci.yml` and `release.yml` move from `macos-latest` to the `xcode-27` runner label.
- **Rationale**: The user chose macOS 27 only (spec Clarifications), which means one error family (`LanguageModelError`). `macos-latest` is currently macOS 26.7 with Xcode 26.6 (SDK 26.5, runner image 20261013), which cannot compile `LanguageModelError`. The `xcode-27` image (macOS 27, Xcode 27) is a GitHub preview. Without the move, the release build would not contain the provider.
- **Alternatives considered**: A `#if compiler(>=6.4)` guard so Xcode 26 still builds (rejected by the user: two code paths, and CI would never compile the adapter); compile guard only (the released app would lack the feature).

## R3: Linking on macOS 13 to 26

- **Decision**: No `Package.swift` change. Rely on automatic weak linking.
- **Rationale**: Spike on 2026-11-19: a Swift 5 mode binary with deployment target macOS 13 that uses `FoundationModels` only behind `#available` gets `LC_LOAD_WEAK_DYLIB` for the framework. ld64 weak-links a dylib when every symbol imported from it is weak, so the app still launches where the framework does not exist. Implementation verifies this on the real `Overtype.app` with `otool -l`.
- **Alternatives considered**: `-weak_framework` via `unsafeFlags` (not needed, and `unsafeFlags` is a build-policy smell).

## R4: Availability

- **Decision**: At the start of every `transform`, read `SystemLanguageModel.availability` on a model created with `useCase: .general` and `guardrails: .permissiveContentTransformations`. Map `.unavailable(reason)` to `ProviderError.onDeviceModelUnavailable(_:)`, with the reasons `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`, and `@unknown default` mapped to `.unknown`. On macOS < 27 the reason is `.operatingSystemTooOld`.
- **Rationale**: `UnavailableReason` is a non-frozen enum in a library-evolution module, so `@unknown default` is required. Checking per run handles Apple Intelligence being turned off after Settings was opened (spec edge case).

## R5: Error mapping (macOS 27 `LanguageModelError`)

| Framework error | Overtype `ProviderError` | Retryable |
|---|---|---|
| `LanguageModelError.contextSizeExceeded(c)` | `.contextWindowExceeded(tokenLimit: c.contextSize)` (new) | no |
| `.rateLimited` | `.rateLimited` (new) | yes (one retry) |
| `.guardrailViolation` | `.responseBlocked(reason: "the on-device safety guardrails")` (existing) | no |
| `.refusal` | `.responseBlocked(reason: "the on-device model refused")` (existing) | no |
| `.unsupportedLanguageOrLocale(c)` | `.unsupportedLanguage(code: c.languageCode.identifier)` (new) | no |
| `.timeout` | `.timeout` (existing) | yes (existing rule) |
| `SystemLanguageModel.Error.assetsUnavailable` | `.onDeviceModelUnavailable(.modelNotReady)` | no |
| `CancellationError` | `.cancelled` (existing) | no |
| any other `LanguageModelError` case, `@unknown default`, any other error | `.onDeviceModelFailed(message:)` (new) | no |

- **Rationale**: Every case has a public initializer (for example `LanguageModelError.GuardrailViolation(debugDescription:)`), so the mapping is unit-tested with real framework values, not mocks, on any macOS 27 machine including the `xcode-27` runner. Reusing `.responseBlocked` keeps the shared error type small: its message ("The AI provider blocked the response (reason: ...). Nothing was changed.") already fits. `.inputTooLargeForContext(limit:)` is not reused because its message counts UTF-8 bytes, which is wrong for a token limit.
- **Message for `.contextWindowExceeded`**: it must say that the selection, the prompt **and the answer** have to fit, because the diagnostic showed two ways to reach it (see R7).

## R6: Generation parameters (model profile)

Diagnostic results (2026-11-19, `respond(to:options:contextOptions:)`):

| Request | Result |
|---|---|
| temperature 0.0, 1.0, 2.0, 5.0, -1 | all succeed, about 0.23 s |
| sampling `.greedy` | succeeds |
| `ContextOptions(reasoningLevel:)` light, moderate, deep, custom("none") | all fail immediately: `LanguageModelError.unsupportedCapability` "The selected model does not support reasoning" |
| `capabilities.contains(.reasoning)` | `false` |

- **Decision**: One profile row: kind `.apple`, model ID `system`, `reasoning: nil`, temperature `.accepted`, source "on-device diagnostic 2026-11-19, macOS 27.2.1, AFM 3 Core Advanced". No `reasoningValues` entry for `.apple`, so the editor hides the reasoning picker and the resolver withholds a hand-edited override with `.providerIgnores`. `suggestedDefaultModel[.apple] = "system"`. The provider never sends `ContextOptions.reasoningLevel`.
- **Rationale**: Sending any reasoning level fails every request. Temperature has no rejected range on this model, so an explicit value is always passed and Automatic sends none.
- **Spec impact**: User Story 4 scenario 3 says an out-of-range temperature is withheld. The diagnostic found no rejected range, so nothing is ever withheld for temperature on this kind. Recorded here for the analyze/reconcile step.

## R7: Context window and output length

Diagnostic results:

| Input | Result |
|---|---|
| `SystemLanguageModel.default.contextSize` | 8192 tokens (macOS 26 back-deploy value was 4096) |
| 5,000 chars of README prose (1,297 tokens) | succeeds in 23.8 s, 1,299 output tokens |
| 40,000 chars (10,362 tokens) | fails in 0.04 s: `contextSizeExceeded`, before any generation |
| 5,000 / 20,000 chars of one repeated sentence | the model loops until the context is full, then `contextSizeExceeded(context=8192, tokens=8193)` after 114 to 166 s |
| `maximumResponseTokens: 20` on long prose | **succeeds silently with truncated text** (out=20, no error, no finish reason) |

- **Decision**: Do not set `maximumResponseTokens`. Bound wall time with the provider's `timeoutSeconds` (R9). Map `contextSizeExceeded` to `.contextWindowExceeded` with a message that covers both input and runaway output.
- **Rationale**: A response-token cap returns truncated text with no signal other than `usage.output.totalTokenCount == cap`, which would let a partial rewrite replace the whole selection (Principle II). Without the cap, a runaway generation ends either in the timeout or in `contextSizeExceeded`; both are typed errors that leave the selection unchanged.
- **Alternatives considered**: Cap output and detect truncation from usage counts (extra logic and a heuristic, for no user benefit over the timeout); pre-count input tokens with `tokenCount(for:)` (oversized input already fails in 0.04 s without generating, and no text leaves the Mac, so a pre-check adds nothing).
- **README impact**: a 5,000-character selection takes about 24 s, so the recipe recommends a 60 s timeout.

## R8: Cancellation

- **Decision**: Rely on structured concurrency. `respond` runs inside the run task; Escape cancels it.
- **Rationale**: Diagnostic: cancelling 0.3 s into a long generation threw `CancellationError` 0.32 s after start, so generation stops promptly (SC-005).

## R9: Hard timeout

- **Decision**: The provider races `respond` against `Task.sleep(timeoutSeconds)` in a throwing task group (the same pattern as `ActionEngine.readWithHardTimeout`) and throws `.timeout` when the sleep wins, cancelling the generation.
- **Rationale**: The URL-based providers get their timeout from `URLSessionConfiguration`; this provider has no URL session, and Principle VI requires a hard timeout.

## R10: Rate limiting of a background app

- **Finding**: 12 back-to-back requests from a command-line process (not frontmost) all succeeded in about 0.24 s each; no `rateLimited` error.
- **Open**: Overtype is a menu bar accessory app that is never frontmost during a run. A command-line process is not proof for that case (Principle III). Quickstart step Q4 runs the real app 15 times in a row from a frontmost text editor and records the result in `docs/compatibility.md`. If it is rate-limited, the typed `.rateLimited` error with one retry is the designed behaviour, and the finding goes into the README.

## R11: Language support

- **Finding**: `supportedLanguages` lists 24 locales (da, de, en, es, fr, it, ja, ko, nb, nl, pt, sv, tr, vi, zh and regional variants). Welsh and Amharic input did **not** raise `unsupportedLanguageOrLocale`; the model answered in English (Amharic: "This is a mock Arabic text.").
- **Decision**: Map the error when it occurs, but do not pre-check the language. Document in the README that the model supports a fixed list of languages and may answer in English, or translate wrongly, for others.
- **Rationale**: Detecting the input language reliably is out of scope, and a pre-check by `NLLanguageRecognizer` would reject mixed-language text that works.

## R12: Settings for a provider with no address and no key

- **Decision**: In `ProvidersTab`, hide the Base URL and API Key fields for `.apple` and show a caption "Runs on this Mac. No network, no API key." The kind label is "Apple on-device", or "Apple on-device (requires macOS 27)" when `#available(macOS 27, *)` fails. In the provider list, an `.apple` row shows "On this Mac (no network)" instead of "Default Endpoint" (Principle V: the user can see where text goes). `SettingsViewModel.saveProvider` stores `baseURL = nil` and `keychainKey = nil` for `.apple`, ignores any key typed, and deletes a stored key when an existing provider switches to `.apple`. A per-kind `Set` (`ModelProfiles.kindsWithoutEndpointOrKey` or similar) holds the rule, following the 010 convention of per-kind data in collections rather than new exhaustive switches.
- **Rationale**: FR-012 and User Story 2. The existing create path always writes `keychainKey: "overtype-<slug>-key"` even when no key is stored; that is acceptable for other kinds but contradicts scenario 2.2 for Apple.

## R13: Model identifier

- **Decision**: The only accepted model ID is `system` (the name `fm` uses for the on-device model). An empty model is impossible after Settings validation; an action-level or hand-edited model other than `system` throws `.modelNotAvailable(model:)` (existing case).
- **Rationale**: `SystemLanguageModel.variant` is read-only on macOS 27; there is no API to choose `core3` or `coreAdvanced3`. Silently ignoring a wrong name would hide a configuration mistake.

## R14: Logging and privacy

- **Decision**: The provider logs nothing itself. `ActionEngine` already logs only `ProviderError.logLabel`, and every new case gets a payload-free label. `.onDeviceModelFailed(message:)` carries Apple's `errorDescription`, which is shown in the HUD only.
- **Rationale**: Principle V. `debugDescription` of framework errors is not used in messages, because its content is not documented.
