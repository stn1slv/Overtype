# Data Model: Model-Aware Generation Parameters

## ActionConfig (changed, persisted in `config.json`)

| Field | Before | After |
|---|---|---|
| `temperature` | `Double`, default `0.0`, always encoded | `Double?`; `nil` means "Automatic" and the key is omitted on encode |
| `reasoningEffort` | (none) | `String?`, provider-native value passed through unchanged; `nil` means "Automatic" and the key is omitted on encode |

Decoding (tolerant, `ConfigDecodingIssues` as today):
- `temperature`: missing or `null` → `nil`; wrong type → `nil` plus an issue naming the key and action id (previously `0.0`).
- `reasoningEffort`: missing or `null` → `nil`; wrong type → `nil` plus an issue; a value that is empty after trimming whitespace → `nil`.
- A stored temperature is kept as written, including values outside 0.0 to 2.0 (the range check applies only to saves from the editor, as today).

Validation on save from the editor: a set temperature must be within 0.0 to 2.0 (existing error code 13); a set reasoning effort is trimmed and stored as text.

## ProviderConfig (unchanged schema)

`defaultModel` stays required. Only the seeded value and the editor's pre-fill change (FR-017, FR-018).

## ModelProfile (new, built into the binary, never persisted)

| Field | Meaning |
|---|---|
| `kind` | `ProviderKind` the profile applies to |
| `modelID` | Exact model ID; matching rules in research R5 |
| `reasoning` | Optional: which parameter (`level` for `reasoning_effort` / `output_config.effort` / `thinkingLevel`, or `thinkingBudget`), the supported values, and the preferred value |
| `temperature` | Rule: `accepted`, `acceptedOnlyAtLevels(Set<String>)`, or `omitted` (rejected or provider says to remove it) |
| `source` | Documentation page and date the profile is based on |

The table content is in `contracts/model-profiles.md`.

## ReasoningSetting (new, value type)

`level(String)` or `thinkingBudget(Int)`. Each provider maps it to its own wire field (contract `request-parameters.md`). A resolver result never carries both Gemini parameters, because there is only one setting.

## DroppableParameter (new, enum)

`temperature`, `reasoning`. The provider-neutral name for a parameter the adaptive fallback may remove. Only `OpenAICompatibleProvider` maps wire names (`temperature`, `reasoning_effort`) onto it.

## ResolvedGenerationParameters (new, value type, output of the resolver)

| Field | Meaning |
|---|---|
| `temperature` | `Double?` to send |
| `reasoning` | `ReasoningSetting?` to send |
| `automaticReasoning` | The value "Automatic" resolves to for this model, for the editor caption (`nil` when there is none) |
| `withheldOverrides` | Overrides the action sets that will not be sent, each with a reason (`modelRejects`, `providerSaysRemove`, `unsupportedValue`, `providerIgnores`, `learnedRejection`), for the editor warning (FR-023) |

Resolution order (pure function, called by `ActionEngine.run` and by the Actions editor):
1. Look up the profile for `(kind, model)`.
2. Reasoning: the override if set, otherwise the profile's preferred value, otherwise none. Withheld when the kind takes no reasoning setting (Ollama), when the profile says the value is unsupported, or when it was learned as rejected.
3. Temperature: the override if set, otherwise none. Withheld for Anthropic (always), when the profile rule is `omitted`, when the rule is `acceptedOnlyAtLevels` and the effective reasoning level is not in that set, or when it was learned as rejected.
4. A model without a profile: overrides pass through unchanged, except the provider-wide rules (Anthropic temperature, Ollama reasoning) and learned rejections.

## TransformRequest (changed, in-memory)

`temperature: Double` becomes `temperature: Double?`, and `reasoning: ReasoningSetting?` is added with a default of `nil`, so existing call sites that pass a `Double` still compile. A helper returns a copy without a given `DroppableParameter`, or `nil` when the request does not carry it.

## ParameterRejectionMemory (new, in-memory, process lifetime)

Key: `(providerID, baseURL.absoluteString, model)`. Value: `Set<DroppableParameter>`. Lock-protected. Read by `ActionEngine.run` before resolving, written by the fallback. Never persisted (research R7).

## ProviderError (changed)

New case `parameterRejected(DroppableParameter, statusCode: Int, message: String)`:
- `errorDescription`: same text as `apiError` ("API Error 400: ...").
- `isRetryable`: `false` (handled by its own branch, not the transient retry).
- `logLabel`: `HTTP <code> (rejected parameter: <name>)`; the message is never in the label.
