# Contract: config.json decode tolerance (after C3)

This contract defines the effective behavior of loading
`~/Library/Application Support/Overtype/config.json`. It supersedes the "missing keys
only" tolerance documented in specs/003-gui-settings for the load path. The stored
schema itself is unchanged; only failure handling changes.

## Guarantees

1. The application always starts. No configuration content can prevent launch or trap
   the process (C1, C3).
2. Valid data always survives. A malformed value affects, at most, its own field or its
   own array element (C3).
3. Nothing is dropped or defaulted silently. Every fallback and every dropped element
   produces a warning log line and contributes to a one-time user-visible notice at
   launch (`loadWarningMessage`). Issue text names keys, ids, and indices only, never
   values (Principle V: the file contains user-authored prompts).

## Behavior by input class

| Input | Behavior | User-visible outcome |
|---|---|---|
| Whole file unreadable (bad JSON, wrong encoding) | Unchanged: defaults in use, timestamped backup preserved, `loadFailureMessage` alert | Alert at launch (existing) |
| Missing section (`global`, `providers`, `actions`) | Unchanged: section default (empty / defaults) | None (existing tolerance) |
| Defaulted scalar has wrong type (e.g. `"showHUD": "true"`) | Field falls back to its default; issue recorded | Warning notice; everything else loads |
| `baseURL` not a parseable URL | Provider loads with nil base URL; issue recorded | Warning notice; provider fails at run time with the existing typed URL error |
| Provider element missing `id`/`kind`/`defaultModel`, or unknown `kind` | That element dropped; issue recorded with id or index | Warning notice; other providers and all actions load |
| Action element missing a required field | That element dropped; issue recorded with id or index | Warning notice; other actions load |
| `shortcut.displayString` missing | Defaults to empty string | None (cosmetic field) |
| `shortcut.keyCode` or `.modifiers` negative | Action loads; shortcut treated as invalid at registration and skipped with a warning naming the action | Warning log; action usable from Settings, hotkey inactive until re-recorded |
| `typingChunkSize` 0, negative, or > 20 (global or per-app) | Value loads as written; resolved cadence clamps to `1...20` at use, warning logged when clamped | Warning log; typing remains complete and bounded |
| `timeoutSeconds`, `retryDelaySeconds` etc. | Unchanged (existing clamps and warnings) | Existing behavior |

## Non-goals

- No schema version field is introduced (tracked in the review backlog).
- Unknown keys are still dropped on the next save (tracked in the review backlog).
- Duplicate provider/action ids are not validated here (tracked in the review backlog).
