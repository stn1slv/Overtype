# Quickstart: Validating Model-Aware Generation Parameters

## Prerequisites

- Xcode toolchain selected (`swift test` needs it; see the project memory note on `DEVELOPER_DIR`).
- For the manual runs: your own OpenAI, Anthropic and Gemini API keys, stored through Settings > Providers.
- A build of the app: `./scripts/build-app.sh`, then re-grant Accessibility (the signature changes).

## Unit tests

```bash
make test
swift test --filter ModelProfilesTests
swift test --filter GenerationParameterResolverTests
swift test --filter TransformRetryTests
swift test --filter AppConfigTests
```

Expected: all pass. The provider body-builder tests cover `contracts/request-parameters.md` row by row.

## Q1. Diagnostic run: does OpenAI name the rejected parameter? (FR-014, run before relying on the fallback)

Run with your own key in your shell; do not paste the key anywhere else.

```bash
curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"gpt-6-luna","temperature":0,"messages":[{"role":"user","content":"Say hi"}]}'

curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"gpt-6-astra","reasoning_effort":"none","messages":[{"role":"user","content":"Say hi"}]}'
```

Expected: HTTP 400 bodies whose `error.param` is `temperature` and `reasoning_effort`. Record both bodies' `error.type`, `error.code` and `error.param` in `docs/compatibility.md`. If `param` is missing, the fallback stays inert (it never fires); record that and keep the profiles as the fix.

Also confirm the inferred Luna rule:

```bash
curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"gpt-6-luna","reasoning_effort":"none","temperature":0,"messages":[{"role":"user","content":"Say hi"}]}'
```

Expected: HTTP 200. If it is a 400, the `gpt-6-luna` profile changes to "temperature omitted" before release.

## Q2. SC-001: an existing config with only the model changed

1. In `config.json`, keep `"temperature": 0` on "Fix grammar" and set the OpenAI provider's `defaultModel` to `gpt-6-luna`.
2. Select text in TextEdit, press the shortcut.

Expected: the selection is replaced on the first request, no error HUD.

## Q3. SC-002: fresh install default

1. Quit Overtype, move `~/Library/Application Support/Overtype/config.json` aside.
2. Launch, add the OpenAI key, run "Fix grammar".

Expected: the seeded provider shows `gpt-6-luna`; the action has no `temperature` or `reasoningEffort` key; the run succeeds. Restore the original file afterwards.

## Q4. SC-003: adaptive fallback on an unprofiled model

Point an action at an OpenAI model without a profile that rejects `temperature`, with `"temperature": 0` stored. Run twice.

Expected: the first run shows "Retrying..." once and succeeds; the second run sends one request (check `/usr/bin/log stream --predicate 'subsystem == "com.github.stn1slv.Overtype"'` for a single warning on the first run only).

## Q5. SC-005: Automatic is faster

For one profiled model per provider, run the same 300-word selection five times with both settings on Automatic, then five times with the reasoning override set to the model's documented default: `gpt-6-luna` (default `medium`), `claude-haiku-5-5` (default `medium`), `gemini-3.8-flash` (default `medium`). Compare medians.

Expected: every Automatic run succeeds on the first request, and each Automatic median is lower.

## Q6. Editor behavior

1. Settings > Actions > Add: both settings show "Automatic".
2. Pick the OpenAI provider with model `gpt-6-luna`: the caption reads "Automatic (none)".
3. Set temperature to 0.7 and reasoning effort to `medium`: a warning says the temperature will not be sent for this model.
4. Switch the provider to Ollama: the reasoning effort control is hidden.
5. Settings > Providers > Add with kind OpenAI: the default model field shows `gpt-6-luna`.

Record Q1 to Q6 results in `docs/compatibility.md`.
