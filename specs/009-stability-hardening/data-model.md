# Data Model: Stability Hardening

No new entities are introduced. This feature changes validation rules, error types, and
load-time semantics of existing entities.

## Configuration (config.json)

Entities: `AppConfig` (root), `GeneralConfig`, `AppTypingOverride`, `ProviderConfig`,
`ActionConfig`, `ActionShortcut`. Structure is unchanged; the following rules change.

### Validation rules (new or changed)

| Entity.field | Rule | Finding |
|---|---|---|
| `ActionShortcut.keyCode`, `.modifiers` | Negative values make the shortcut invalid; an invalid shortcut is skipped at registration with a warning, never trapped on | C1 |
| `ActionShortcut.displayString` | Tolerates absence (defaults to empty string); cannot drop the action | C3 |
| `GeneralConfig.typingChunkSize`, `AppTypingOverride.typingChunkSize` | Resolved value clamped to `1...20` before use; warning when clamped | C2 |
| `GeneralConfig.typingDelayMicroseconds`, `AppTypingOverride.typingDelayMicroseconds` | Resolved value clamped to `>= 0` (existing `0...1_000_000` scaling clamp unchanged) | C2 |
| `ProviderConfig.baseURL` | Decoded as string, converted with `URL(string:)`; failure yields nil plus a load issue, never a decode abort | C3 |
| All defaulted scalars (`showHUD`, `typingSpeedMultiplier`, `timeoutSeconds`, `retryDelaySeconds`, `temperature`, `maxInputCharacters`, `allowNewlines`, `writeStrategy`, `enabled`, `model`) | Fall back to their default on type mismatch as well as absence, recording a load issue | C3 |
| `providers[]`, `actions[]` elements | Decoded individually; an unsalvageable element (missing required field, unknown `kind`) is dropped alone, recording a load issue with its id or index | C3 |

Required per element (unchanged): provider `id`, `kind`, `defaultModel`; action `id`,
`title`, `providerID`, `systemPrompt`, `userPromptTemplate`.

### Load-time state (ConfigStore)

| Field | Meaning |
|---|---|
| `loadFailureMessage` (existing) | Whole file unreadable; defaults in use; backup preserved |
| `loadWarningMessage` (new) | File readable, but fields fell back or elements were dropped; lists keys/ids only, never values |
| `ConfigDecodingIssues` (new, transient) | Reference collector passed via `JSONDecoder.userInfo`; accumulates issue strings during decode |

State transition: `reload()` (existing, gains callers per C7) replaces the in-memory
config from disk; `SettingsViewModel.lastLoaded` (new, in-memory) snapshots the last
config adopted by the UI and is refreshed on init, successful save, and successful
external-edit adoption.

## Credential (Keychain item)

Identity: account-only (`kSecClass` = generic password, `kSecAttrAccount` = keychain key
string). Unchanged, deliberately (existing credentials keep working).

Lifecycle change (C4): replace = find, then update-in-place, else add. The previous
value is never deleted ahead of a durable write. Deletion semantics unchanged
(idempotent, `errSecItemNotFound` is success).

## Errors (typed values)

| Type.case | Status | Finding |
|---|---|---|
| `AXError.writeIncomplete` | NEW: replacement delivery failed after the destructive delete; message states the document may be partially replaced | H3 |
| `AXError.accessibilityPermissionRevoked` | NEW: trust check failed at run start; message points to System Settings | H4 |
| `KeychainError` + `LocalizedError` | CHANGED: renders `OSStatus` numerically plus system message text | C4 |
| `ProviderError.responseBlocked(reason:)` | Reused for OpenAI-compatible refusal / content filter (short category as reason) | H5 |
| `ProviderError.emptyResponse` | Reused for OpenAI-compatible null/empty content | H5 |
| `ProviderError.outputTruncated` | NEW (post-review): `finish_reason == "length"`; partial output is refused rather than written | H5 |
| `AXError.readTimedOut` | NEW: 30 s read-phase hard timeout; message names the unresponsive target application | H1 |

## Notifications

| Name | Status | Purpose |
|---|---|---|
| `.overtypeConfigDidChange` (existing) | Also posted after a successful external-edit adoption in `reloadFromDisk()` | C7 |
| `.overtypeAccessibilityTrustLost` | NEW: posted by the engine when the per-run trust check fails; AppDelegate starts the poll/reinstall timer | H4 |

## Logging / diagnostics state

| Item | Rule |
|---|---|
| `Logger.isDebugEnabled` | Initialized from `UserDefaults` key `OvertypeDebugLogging`; enabling emits one `.warning` privacy notice | H7 |
| Unified log format | `%{public}@` with the composed message string | H7 |
| Load issues, clamp warnings, keychain statuses | Keys, ids, titles, counts, and status codes only; never selected text, prompts, model output, or key values | V |
