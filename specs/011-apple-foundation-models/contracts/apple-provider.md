# Contract: Apple Foundation Models Provider

The provider exposes no network or file interface. Its contract is the `AIProvider` protocol plus the configuration record users write by hand.

## AIProvider behaviour

`AppleFoundationModelProvider.transform(_ request: TransformRequest) async throws -> String`

| Input | Use |
|---|---|
| `request.systemPrompt` | Session instructions |
| `request.userPromptTemplate` with `{{text}}` replaced by `request.text` | The prompt |
| `request.model` | Must be `system` |
| `request.temperature` | `GenerationOptions.temperature` when non-nil; omitted otherwise |
| `request.reasoning` | Never sent (the model rejects every reasoning level) |

Guarantees:

1. Calls only the in-process `FoundationModels` framework. No `URLSession`, no `Process`, no socket.
2. Creates a new `LanguageModelSession` per call; no state survives between calls.
3. Uses `SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)`.
4. Checks availability before generating, on every call.
5. Never sets `maximumResponseTokens` (a cap truncates silently, research R7).
6. Ends within `timeoutSeconds` (plus cancellation latency) with a result or a typed error.
7. Throws only `ProviderError` values, mapped as in research R5.
8. Logs nothing.

## Static seams for unit tests

| Function | Availability | Purpose |
|---|---|---|
| `static func error(for reason: SystemLanguageModel.Availability.UnavailableReason) -> ProviderError` | macOS 27 | availability mapping |
| `static func providerError(from error: Error) -> ProviderError` | macOS 27 | framework error mapping |

Tests construct real framework values through their public initializers and skip with `XCTSkip` on macOS < 27. Tests of `ProviderError` messages, retryability and log labels run on every OS.

## Configuration record

See `data-model.md`. Minimal valid record: `{"id": "apple", "kind": "apple", "defaultModel": "system", "timeoutSeconds": 60}`.
