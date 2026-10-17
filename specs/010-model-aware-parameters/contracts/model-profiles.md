# Contract: Built-in Model Profiles (initial content)

Source date for every row: 2026-10-17. Research entries: OpenAI R1, Anthropic R3, Gemini R4. Matching rules: research R5. Every row is a claim to verify; a wrong row is corrected in a release, and for OpenAI the adaptive fallback keeps runs working meanwhile.

Temperature rules: **accepted**; **only at X** (accepted only when the effective reasoning level is X); **omitted** (never sent, even when the action sets one).

## OpenAI-compatible (`reasoning_effort`)

| Model ID | Supported values | Preferred | Temperature |
|---|---|---|---|
| `gpt-6-luna` | none, low, medium, high, xhigh, max | none | only at none |
| `gpt-6-sol` | none, low, medium, high, xhigh, max | none | only at none |
| `gpt-6-astra` | low, medium, high, xhigh, max | low | omitted |
| `gpt-6.1-sol` | low, medium, high, xhigh, max | low | omitted |

## Anthropic (`output_config.effort`)

Temperature is omitted for every Anthropic request by provider rule, so the column is not repeated.

| Model ID | Supported values | Preferred |
|---|---|---|
| `claude-fable-5-1` | low, medium, high, xhigh, max | low |
| `claude-mythos-5-1` | low, medium, high, xhigh, max | low |
| `claude-fable-5` | low, medium, high, xhigh, max | low |
| `claude-mythos-5` | low, medium, high, xhigh, max | low |
| `claude-mythos-preview` | low, medium, high, max | low |
| `claude-opus-5-5` | low, medium, high, xhigh, max | low |
| `claude-opus-5` | low, medium, high, xhigh, max | low |
| `claude-opus-4-8` | low, medium, high, xhigh, max | low |
| `claude-opus-4-7` | low, medium, high, xhigh, max | low |
| `claude-opus-4-6` | low, medium, high, max | low |
| `claude-opus-4-5` (matches `claude-opus-4-5-20251101`) | low, medium, high | low |
| `claude-sonnet-5-5` | low, medium, high, xhigh, max | low |
| `claude-sonnet-5` | low, medium, high, xhigh, max | low |
| `claude-sonnet-4-6` | low, medium, high, max | low |
| `claude-haiku-5-5` | low, medium, high, xhigh, max | low |

## Gemini (`thinkingLevel` or `thinkingBudget`)

| Model ID | Parameter | Supported values | Preferred | Temperature |
|---|---|---|---|---|
| `gemini-4-argon` | thinkingLevel | low, medium, high | low | omitted |
| `gemini-3.8-flash` | thinkingLevel | low, medium, high | low | omitted |
| `gemini-3.7-flash` | thinkingLevel | low, medium, high | low | omitted |
| `gemini-3.6-flash` | thinkingLevel | minimal, low, medium, high | minimal | omitted |
| `gemini-3.5-flash` | thinkingLevel | minimal, low, medium, high | minimal | omitted |
| `gemini-3.5-flash-lite` | thinkingLevel | minimal, low, medium, high | minimal | omitted |
| `gemini-3.1-flash-lite` | thinkingLevel | minimal, low, medium, high | minimal | omitted |
| `gemini-3-flash-preview` | thinkingLevel | minimal, low, medium, high | minimal | omitted |
| `gemini-3.1-pro-preview` | (none recorded) | | | omitted |
| `gemini-2.5-pro` | thinkingBudget | 128 to 32768 | 128 | accepted |
| `gemini-2.5-flash` | thinkingBudget | 0 to 24576 | 0 | accepted |

For a `thinkingBudget` model, a text override (for example `low`) is not a valid value and is withheld with reason `unsupportedValue`; the editor warns.

## Editor value lists (per provider kind, FR-022)

| Kind | Values offered after "Automatic" |
|---|---|
| OpenAI-compatible | none, minimal, low, medium, high, xhigh, max |
| Anthropic | low, medium, high, xhigh, max |
| Gemini | minimal, low, medium, high |
| Ollama | (setting not offered) |

## Suggested default model (FR-017, FR-018)

| Kind | Suggested `defaultModel` |
|---|---|
| OpenAI-compatible | `gpt-6-luna` |
| others | (none: field stays empty) |
