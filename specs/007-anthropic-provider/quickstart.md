# Quickstart: Anthropic Claude Model Support

**Feature**: `007-anthropic-provider` | **Date**: 2026-08-06

How to validate this feature, from fastest to slowest: pure-logic tests, then a
configuration recipe, then the live manual acceptance procedure.

---

## 1. Automated pure-logic tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AnthropicProviderTests
```

> The `DEVELOPER_DIR` prefix is required when the active toolchain is Command
> Line Tools rather than Xcode; without it `swift test` fails with
> `no such module 'XCTest'`. Check with `xcode-select -p`.

Covers, without any network access:

- Text extraction from a single `text` block, and concatenation across several.
- **Reasoning filtering** — a `thinking` block preceding the answer is skipped
  (FR-008 / SC-005, the highest-risk behaviour in this feature).
- An unrecognised block type is skipped rather than written.
- `stop_reason: "max_tokens"` with non-empty text is a success.
- `stop_reason: "refusal"` → `.responseBlocked`, including the
  `stop_details.category` detail when present.
- Any other non-normal `stop_reason` → `.responseBlocked`.
- Empty / all-filtered content → `.emptyResponse`.
- Non-JSON or structurally invalid body → `.invalidResponse`.
- Endpoint construction: the default base, and a `baseURL` override with and
  without a trailing slash.

Config decoding for `"kind": "anthropic"` is covered in `AppConfigTests`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppConfigTests
```

Full suite:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

---

## 2. Configure an Anthropic provider

Either add it in **Settings → Providers** (Anthropic now appears in the kind
picker), or edit `~/Library/Application Support/Overtype/config.json` directly:

```json
{
  "id": "anthropic",
  "kind": "anthropic",
  "defaultModel": "claude-haiku-4-5",
  "timeoutSeconds": 30,
  "retryDelaySeconds": 0.5,
  "keychainKey": "overtype-anthropic-key"
}
```

`baseURL` is omitted deliberately — the provider defaults to
`https://api.anthropic.com/v1/`. Set it only to route through a proxy.

Store the key (Settings does this for you; this is the manual equivalent):

```sh
security add-generic-password -a "overtype-anthropic-key" -s "Overtype" -w
```

Then point an action at it by setting that action's `providerID` to `anthropic`.

> **The action's `temperature` is ignored for Anthropic runs.** Current Claude
> models reject the field, so it is never sent. It still applies to `openai` and
> `gemini` providers.

---

## 3. Manual acceptance (live boundary)

System-boundary behaviour is verified by hand, not by mocks (Principle VIII).
Run these against a real API key and record the outcome in the
`### Anthropic (native /v1/messages)` subsection of `docs/compatibility.md`.
The `#` IDs map one-for-one to the rows in that table.

| # | Scenario | Steps | Expected |
|---|---|---|---|
| A1 | Happy path | Select a sentence with a grammar error in a known-supported app; press the action shortcut | Selection replaced by the corrected text; Reading → Thinking → Writing HUD shown |
| A2 | Cancellation | Trigger the action, press Escape before the write | Run aborts; selection unchanged |
| A3 | Context change | Trigger the action, switch app before the write completes | Write aborted; original document untouched |
| A4 | Missing key | Remove the Keychain item, trigger the action | Specific "API key missing" error; no network call; selection unchanged |
| A5 | Invalid key | Store a bogus key, trigger the action | Specific HTTP 401 error; selection unchanged |
| A6 | Unknown model | Set `defaultModel` to `claude-does-not-exist`, trigger | Specific HTTP 404 error; selection unchanged |
| A7 | Declined response | Send a prompt the model declines | Specific "blocked" error naming the reason; selection unchanged |
| A8 | Network down | Disable networking, trigger the action | Specific network error after the single retry; selection unchanged |
| A9 | **Reasoning not written** | Set the action's model to `claude-opus-5` (which reasons by default) and run A1 | Only the answer text is written. **No reasoning prose appears in the document** |
| A10 | Rate limit retry | If a 429 can be provoked, trigger the action | HUD shows `Retrying...` once, then either success or a specific error; selection unchanged |

**A9 is the item that must not be skipped.** It is the only live check of FR-008,
and its failure mode is silent corruption of the user's document rather than a
visible error. A1–A8 all still pass with a broken reasoning filter.

---

## 4. Privacy checks

Run alongside A1:

```sh
# Bare `log` is shadowed by a zsh builtin — use the absolute path.
/usr/bin/log stream --predicate 'subsystem CONTAINS "overtype"' --level info
```

Confirm during a full run that **none** of the following appear at `info` or
above: the API key, the selected text, the model output, or a server error
message body. Provider failures must appear only as a short label such as
`HTTP 401`, never as the full `errorDescription`.

Also confirm the key never reaches the request address — it travels in the
`x-api-key` header, and the URL contains no query string at all.

---

## Success criteria mapping

| Criterion | Verified by |
|---|---|
| SC-001 (enable in under 5 min) | Section 2, both the Settings path and the config-file path |
| SC-002 (100% of failures specific, selection intact) | A4, A5, A6, A7, A8, A10 |
| FR-011 (transient failures get the existing single retry) | **A10**, plus the 529 assertion in `ProviderErrorRetryTests` |
| SC-003 (same feedback stages) | A1, A2 |
| SC-004 (no key/text/output in logs) | Section 4 |
| SC-005 (reasoning never written) | **A9**, plus the pure-logic filter tests in section 1 |
| SC-006 (no change to existing actions) | Full `swift test` in section 1; existing `openai`/`gemini` actions still run |
