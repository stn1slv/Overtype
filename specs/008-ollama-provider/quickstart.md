# Quickstart / Validation Guide: Local Ollama Model Support

**Feature**: `008-ollama-provider` | **Date**: 2026-08-06

How to prove this feature works end to end. Unit tests cover the pure logic;
everything touching the network, the Accessibility API, or the app bundle is
verified by hand and recorded in `docs/compatibility.md` (Principle VIII).

---

## Prerequisites

The build needs none of these. The acceptance run needs all of them.

```bash
# 1. The service (already present on the dev machine at /opt/homebrew/bin/ollama)
ollama --version

# 2. Start it (it was NOT running when this plan was written)
ollama serve            # leave running in its own terminal

# 3. Confirm it answers
curl -s http://localhost:11434/api/version

# 4. Install the recipe model (a few hundred MB)
ollama pull llama3.2

# 5. Install a small reasoning model, needed by acceptance item O12
ollama pull deepseek-r1:1.5b

ollama list             # both must appear
```

If `ollama pull llama3.2` fails because the name is no longer distributed,
substitute a model meeting the same three criteria — small, no reasoning by
default, generally available — and update the README recipe, `research.md` R11,
and this file together.

## Build and unit tests

```bash
make build
make test
```

`swift test` needs the Xcode toolchain. With Command Line Tools active it fails
with `no such module 'XCTest'`; prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Expected: existing tests unchanged and green, plus the new
`OllamaProviderTests`. Run the tests **before** starting work as well, to confirm
a green baseline.

## Configure the provider

Either path must work; both are part of acceptance (US2).

**Path A — Settings UI.** Open Settings → Providers → Add Provider. Choose
`Ollama` from the kind list (it must appear, with no "not implemented"
qualifier). Leave Base URL empty, set Default Model to `llama3.2`, leave the API
Key field **empty** — its prompt must read as optional — and save.

**Path B — configuration file.** Add to
`~/Library/Application Support/Overtype/config.json`:

```json
{
  "id": "ollama-local",
  "kind": "ollama",
  "defaultModel": "llama3.2",
  "timeoutSeconds": 30
}
```

Then point an existing action's `providerID` at `ollama-local`, or create one in
Settings → Actions.

## Acceptance scenarios

Run from the built bundle (`./scripts/build-app.sh`, then open `Overtype.app`),
not the raw executable. Re-grant Accessibility after every rebuild: the
permission is bound to the code signature.

| # | Covers | Steps | Expected |
|---|---|---|---|
| O1 | US1, FR-003 | Select a sentence with a grammar error in TextEdit, press the action shortcut | Selection is replaced by the corrected text; HUD shows Reading → Thinking → Writing |
| O2 | US1, FR-012 | Repeat O1 and press Escape while "Thinking" is shown | Run aborts, selection unchanged |
| O3 | US2 path A | Configure via Settings with an empty key field | Provider saves; action runs; **no** "API Key is missing" error |
| O4 | US2 path B | Configure via `config.json` only, restart the app | Provider is registered and the action runs |
| O5 | US2, FR-007 | Leave Base URL empty | Request reaches `http://localhost:11434`; run succeeds |
| O6 | FR-008, R9 | Perform O1 from the **bundle** | Succeeds. If it fails with `-1022` (`NSURLErrorAppTransportSecurityRequiresSecureConnection`), add `NSAppTransportSecurity → NSAllowsLocalNetworking` to `Sources/Overtype/Resources/Info.plist` with a comment naming this feature, rebuild, and re-run |
| O7 | US3, FR-013 | Stop the service (`Ctrl-C` on `ollama serve`), run the action | Specific error naming the address, says the service does not appear to be running; selection unchanged; **no retry delay observed** |
| O8 | US3, FR-013 | Restart the service, set the action's model to `does-not-exist`, run | Specific error naming that model as not installed; selection unchanged; no retry |
| O9 | US3 | Set `timeoutSeconds` to 5, run against a cold large model | Standard timeout error; selection unchanged |
| O10 | US4, SC-004 | Turn off Wi-Fi and unplug Ethernet, run O1 | Succeeds |
| O11 | US4, SC-005 | Run O1 with Console filtered on the app, or a network monitor | Only `localhost:11434` is contacted |
| O12 | FR-009 | Configure a reasoning-capable model (for example a `deepseek-r1` variant) and run O1 | Only the answer is written; no reasoning text and no `<think>` markers appear in the document |
| O13 | FR-019, SC-007 | Run O1 with debug logging off, then inspect logs | Neither the selection nor the output appears; `/usr/bin/log` — the bare `log` is shadowed by a zsh builtin |
| O14 | SC-008 | Run one existing OpenAI/Gemini/Anthropic action | Behaves exactly as before |
| O15 | FR-010a | Set an action's Max Characters to 5000, select ~5000 characters, run | Whole selection is rewritten; no silent shortening of the input |
| O16 | FR-010b | Raise the action's Max Characters to its maximum, select more than 6000 characters, run | Specific error naming the byte limit in force (6000 on a large-window model, less on a small one) and telling you to select less text; the transformation request is not sent, selection unchanged, no retry delay |
| O17 | FR-010b, R13 | Configure a small-window model (`ollama pull tinyllama`, window 2048) and select ~2000 characters | Refused with a limit of 768, not 6000 — the budget follows the model's own window |

O12's second model is now pulled in step 5 of the prerequisites, so it should
always be executable. If that pull fails and no substitute reasoning model is
available, record O12 as **not executed** rather than as passed: layer 2 of the
reasoning filter is unit-tested, but layer 1 against a real thinking model is
not, and SC-006 would then be only half verified.

## Constitution PR checklist

```bash
rg NSPasteboard Sources/          # must return nothing outside comments
make lint
make test
```

Plus: no secret, selected text, or model output logged at `info` or above; every
new boundary workaround commented; O1-O16 executed and recorded in
`docs/compatibility.md`.
