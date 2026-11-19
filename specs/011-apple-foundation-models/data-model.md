# Data Model: Apple Foundation Models Provider

## ProviderKind (changed)

New case `apple`, raw value `"apple"`. Existing raw values are unchanged, so existing configuration files decode as before.

## ProviderConfig with `kind: "apple"`

| Field | Rule for the Apple kind |
|---|---|
| `id` | As for every kind (slug, unique). |
| `kind` | `"apple"` |
| `baseURL` | Always `nil` when saved from Settings. A hand-edited value is loaded but ignored by the provider. |
| `defaultModel` | `"system"`, pre-filled in Settings (`ModelProfiles.suggestedDefaultModel[.apple]`). An empty value (hand-edited) also means the system model; any other value fails the run with `modelNotAvailable`. |
| `timeoutSeconds` | As for every kind. README recipe uses 60. |
| `retryDelaySeconds` | As for every kind. |
| `keychainKey` | Always `nil` when saved from Settings. Switching an existing provider to `.apple` deletes its stored Keychain item. A hand-edited value is ignored. |

Example record:

```json
{
  "id": "apple",
  "kind": "apple",
  "defaultModel": "system",
  "timeoutSeconds": 60,
  "retryDelaySeconds": 0.5
}
```

## ProviderError (changed)

New cases. Each gets an `errorDescription`, an `isRetryable` value and a payload-free `logLabel`.

| Case | Payload | Retryable | logLabel |
|---|---|---|---|
| `onDeviceModelUnavailable(OnDeviceModelUnavailability)` | reason | no | `on-device model unavailable` |
| `contextWindowExceeded(tokenLimit: Int)` | limit in tokens | no | `context window exceeded` |
| `unsupportedLanguage(code: String)` | language code | no | `unsupported language` |
| `rateLimited` | none | **yes** | `rate limited` |
| `onDeviceModelFailed(message: String)` | Apple's description | no | `on-device model failed` |

Reused cases: `.responseBlocked(reason:)`, `.timeout`, `.cancelled`, `.modelNotAvailable(model:)`, `.emptyResponse`.

## OnDeviceModelUnavailability (new)

Plain Swift enum, available on every macOS version so it can be tested anywhere.

| Case | Message (in `ProviderError.errorDescription`) |
|---|---|
| `operatingSystemTooOld` | The Apple on-device model requires macOS 27 or later. Nothing was changed. |
| `deviceNotEligible` | This Mac does not support Apple Intelligence, so the on-device model cannot run. Nothing was changed. |
| `appleIntelligenceNotEnabled` | Turn on Apple Intelligence in System Settings to use the on-device model. Nothing was changed. |
| `modelNotReady` | The on-device model is not ready yet (it may still be downloading). Try again later. Nothing was changed. |
| `unknown` | The on-device model is not available right now. Nothing was changed. |

## ModelProfile row (new)

| kind | modelID | reasoning | temperature | source |
|---|---|---|---|---|
| `.apple` | `system` | `nil` | `.accepted` | on-device diagnostic 2026-11-19, macOS 27.2.1, AFM 3 Core Advanced |

Per-kind data: `suggestedDefaultModel[.apple] = "system"`; no `reasoningValues` entry; not in `kindsWithoutTemperature`; member of the new set of kinds that take no endpoint and no key.

## Run-time states (one `transform` call)

```text
start
  -> OS < 27                    -> throw onDeviceModelUnavailable(.operatingSystemTooOld)
  -> model not "" or "system"   -> throw modelNotAvailable(model)
  -> availability unavailable   -> throw onDeviceModelUnavailable(reason)
  -> generate (fresh session, permissive guardrails, temperature if any)
       -> Escape                -> cancelled
       -> timeoutSeconds passes -> timeout (generation cancelled)
       -> framework error       -> mapped error (research R5)
       -> text                  -> blank? emptyResponse : return text
```
