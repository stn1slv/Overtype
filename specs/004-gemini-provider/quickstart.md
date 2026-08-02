# Quickstart: Validate Gemini Model Support

**Feature**: 004-gemini-provider | **Date**: 2026-08-02

This guide proves the feature works end to end. It has two parts: automated
pure-logic tests, and a manual acceptance procedure for the live HTTP boundary
(required by Principle VIII and recorded in `docs/compatibility.md`).

## Prerequisites

- A Google Gemini API key from Google AI Studio.
- A debug build of Overtype with Accessibility permission granted (re-grant after
  any rebuild; the permission is bound to the code signature).
- Reference: request/response shape in
  [`contracts/gemini-generatecontent.md`](./contracts/gemini-generatecontent.md);
  field usage in [`data-model.md`](./data-model.md).

## 1. Automated pure-logic tests

```sh
swift test --filter GeminiProviderTests
```

Expected: all cases pass, covering the parsing/mapping intents in the contract
(success text, multi-part concatenation, blocked → `.responseBlocked`, empty →
`.emptyResponse`, non-200 → `.apiError`, malformed → `.invalidResponse`).

Also run the full suite to confirm no regression:

```sh
swift test
```

## 2. Configure a Gemini provider (documentation recipe)

Add a provider block to `~/Library/Application Support/Overtype/config.json` and
point an existing action at it (README documents this; the shipped default config
is unchanged):

```json
{
  "id": "gemini",
  "kind": "gemini",
  "defaultModel": "gemini-3.5-flash-lite",
  "timeoutSeconds": 30,
  "keychainKey": "gemini-api-key"
}
```

Store the key in the Keychain (via the app's key entry, or `security`):

```sh
security add-generic-password -a "$USER" -s "gemini-api-key" -w "<YOUR_GEMINI_KEY>" -U
```

Set an action's `providerID` to `"gemini"` (optionally set the action `model`).

## 3. Manual acceptance (live boundary)

Perform each in a known-supported app (e.g. TextEdit) and record the result in
`docs/compatibility.md`.

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| A1 | Happy path | Select a sentence with a typo, press the Gemini action shortcut | HUD shows Reading → Thinking → Writing; selection is replaced by the corrected text |
| A2 | Cancellation | Trigger the action, press Escape before writing | Run cancels; selection unchanged |
| A3 | Context change | Trigger, then switch app / click elsewhere before writing completes | Write aborts (`contextChanged`); selection unchanged |
| A4 | Missing key | Remove/blank the Keychain item, trigger | Specific "API Key is missing" error; selection unchanged |
| A5 | Invalid key | Set a wrong key, trigger | Specific API error surfacing the server message (401/400); selection unchanged |
| A6 | Unknown model | Set action `model` to a bogus name, trigger | Specific API error (unknown model); selection unchanged |
| A7 | Safety block | Craft input that Gemini blocks | Specific "blocked" error with reason; selection unchanged |
| A8 | Network down | Disable network, trigger | Specific network error; selection unchanged |

## 4. Privacy checks (must all hold)

- `rg NSPasteboard Sources/` returns no match outside comments.
- With debug logging off, run a Gemini action and inspect logs: neither the
  selected text, the model output, nor the API key appears.
- The API key never appears in `config.json`, `UserDefaults`, error messages, or
  the UI, and never in a request URL (it is sent as the `x-goog-api-key` header).

## Success criteria mapping

- A1 + step 2 → SC-001 (enable and run in under 5 minutes), SC-003 (same
  feedback stages).
- A4–A8 → SC-002 (100% of failure cases give a specific error, selection intact).
- Step 4 → SC-004 (no secret/selected text/output leakage).
- Full-suite pass + unchanged default config → SC-005 (no regression to existing
  providers/actions).
