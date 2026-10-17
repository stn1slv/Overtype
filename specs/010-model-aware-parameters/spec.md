# Feature Specification: Model-Aware Generation Parameters

**Feature Branch**: `010-model-aware-parameters`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "Optional per-action temperature and reasoning effort for the OpenAI-compatible provider. Problem: OpenAICompatibleProvider always sends the action's `temperature`; OpenAI reasoning models such as gpt-6-luna (default reasoning effort `medium`) reject any temperature other than the default with HTTP 400 (\"Unsupported value: 'temperature' does not support 0 with this model. Only the default (1) value is supported.\"). OpenAI docs (Using GPT-6 guide, gpt-6-luna model page): when reasoning effort is not `none`, remove `temperature`, `top_p`, `top_logprobs`; gpt-6-luna and GPT-6 Sol support `reasoning_effort: \"none\"` (Chat Completions) which re-enables temperature and suits latency-critical tasks; GPT-6 Astra and GPT-6.1 Sol do not support `none`. Goal: (1) make action `temperature` optional; when unset the request omits it so the model uses its default; (2) add an optional per-action `reasoningEffort`; when set, the OpenAI-compatible request sends `reasoning_effort`, otherwise omits it. [...] Settings > Actions editor must let the user choose \"model default\" for temperature and pick or clear a reasoning effort. Request-body construction must be unit-testable as pure logic." Follow-ups from the user: "the project should know some details (and specifics regarding models) rather the end user who wants to use this project"; "also recheck https://platform.claude.com/llms.txt for anthropic models"; "also recheck google's apis https://ai.google.dev/api"; "also let's make gpt-6-luna a default model for openai (if user is not defined another)".

## Clarifications

### Session 2026-10-17

- Q: Who should know model-specific parameter rules? → A: The project, not the end user. Overtype ships built-in model profiles. This reverses the original description's "no per-model list" position. The concern behind that position (feature 007: a list goes stale and turns into a hard failure) is answered per provider below: for every provider, a model without a profile gets a request that works today, and for OpenAI an adaptive fallback also covers models that reject a parameter.
- Q: Should the action editor still let the user set temperature and reasoning effort? → A: Yes, as an advanced override. Both default to "Automatic" (the project decides). A user value wins over the profile's preferences, but not over a documented limit of the model.
- Q: For OpenAI, how are models without a profile handled? → A: Built-in profiles plus an adaptive fallback: when OpenAI rejects a parameter and its structured error names that parameter, Overtype retries once without it and remembers that for the model during the session.
- Q: How should Overtype learn rules for Anthropic and Gemini models? → A: Built-in profiles only, no runtime capability lookup. The adaptive fallback is not possible for them: Anthropic's error body has only `type` and `message`, and Google documents no field that names a rejected parameter, while matching message text is forbidden (FR-016). It is not needed either: a model without a profile gets today's request, which the providers accept, so a stale profile costs the latency optimization, not the run. Both providers' Models APIs report some capabilities (Anthropic: effort levels and thinking types; Gemini: thinking flag and default and maximum temperature), but neither reports everything Overtype needs, and a lookup would add a network call, a cache and a new failure path; it is left for a later feature.
- Q: Gemini 3.x and 4: Google's documentation says to remove `temperature` from all requests, but existing configurations store `temperature: 0` only because the editor required a value. What happens? → A: The profile omits it. A temperature is not sent to a model whose profile says the provider's documentation tells clients to remove it, even when the action stores one, and the editor says so.
- Default chosen without asking (reversible): Anthropic keeps feature 007's rule of never sending `temperature`. The twelve newest Claude models reject any non-default value; sending it to older models only would be exactly the list 007 refused, and the latency gain for Anthropic comes from effort, not temperature. What changes for Anthropic is that profiled models now get a reasoning effort.
- Q: Which OpenAI model should Overtype use when the user has not chosen one? → A: `gpt-6-luna`. It becomes the default model of the seeded OpenAI provider and the pre-filled model for a new OpenAI provider; models the user already configured are never changed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Current models work with no extra setup (Priority: P1)

A user changes the model of the "Fix grammar" action to `gpt-6-luna`. Today every run fails with "API Error 400: Unsupported value: 'temperature' does not support 0 with this model". After this feature, the run succeeds without the user changing any other setting, because Overtype knows how to talk to that model. The same holds for current Claude and Gemini models. The user does not need to know what temperature, reasoning effort or thinking level mean.

**Why this priority**: This is the reported defect, and the user's explicit requirement is that model details are the project's responsibility.

**Independent Test**: Take an existing configuration whose action stores temperature 0, change only the model to `gpt-6-luna`, run the action in a supported app, and confirm the selection is replaced with no error. Repeat with a profiled Claude model and a profiled Gemini 3.x model.

**Acceptance Scenarios**:

1. **Given** an action that stores temperature 0 and uses `gpt-6-luna`, **When** the user runs it, **Then** the selection is replaced on the first request, with no error.
2. **Given** an action on a model that has a built-in profile, **When** the user runs it with both settings on "Automatic", **Then** the request uses the profile's settings for that model.
3. **Given** an action that stores temperature 0 and uses a Gemini model whose profile says to remove temperature, **When** the user runs it, **Then** the request carries no temperature.
4. **Given** an action on a model with no built-in profile that works today, on any provider, **When** the user runs it after upgrading, **Then** the request is identical to the request sent before the upgrade.

---

### User Story 2 - New users start on a current OpenAI model (Priority: P1)

A user installs Overtype for the first time, or adds a new OpenAI provider in Settings. The provider's default model is `gpt-6-luna` unless the user types a different one. A user who already has a provider configured keeps their model.

**Why this priority**: The first experience should use a current model that Overtype knows how to call, and the user asked for this default.

**Independent Test**: Start with no configuration file, launch Overtype, and confirm the seeded OpenAI provider's default model is `gpt-6-luna` and "Fix grammar" works. Then add a new OpenAI provider in Settings and confirm the model field is pre-filled with `gpt-6-luna`.

**Acceptance Scenarios**:

1. **Given** no configuration file exists, **When** Overtype launches, **Then** the seeded OpenAI provider's default model is `gpt-6-luna` and the seeded action uses "Automatic" for both settings.
2. **Given** the user adds a new provider of the OpenAI kind in Settings, **When** the editor opens, **Then** the default model field contains `gpt-6-luna`, and the user can replace it.
3. **Given** an existing configuration with any OpenAI default model, **When** Overtype is upgraded, **Then** that model is not changed.

---

### User Story 3 - Unknown OpenAI models adapt instead of failing (Priority: P1)

A new OpenAI model is released after the current Overtype version, or the user points the OpenAI-compatible provider at another service. The model rejects a parameter Overtype sends. Instead of showing an error, Overtype retries once without that parameter, the run succeeds, and later runs with that model in the same session skip the parameter from the start.

**Why this priority**: OpenAI profiles always lag behind new models, and for OpenAI a stale profile or a stored temperature turns into a 400 error.

**Independent Test**: Use an OpenAI model with no profile that rejects `temperature` (or simulate one in a unit test), run the action, and confirm the run succeeds after one extra request; run it again and confirm only one request is sent.

**Acceptance Scenarios**:

1. **Given** an OpenAI model with no profile that rejects a parameter Overtype sent and the structured error names it, **When** the user runs the action, **Then** Overtype retries once without that parameter and the selection is replaced.
2. **Given** that a parameter was learned as rejected for a model during this session, **When** the user runs an action on the same provider and model again, **Then** the first request does not contain that parameter.
3. **Given** the provider rejects the request with a 400 error that does not name a parameter Overtype can drop, **When** the user runs the action, **Then** no adaptive retry happens and the existing typed error is shown.
4. **Given** an adaptive retry is in progress, **When** the user presses Escape, **Then** the run is cancelled and the selection is unchanged.

---

### User Story 4 - Advanced users can override the automatic choice (Priority: P2)

An advanced user wants more careful rewrites from a "Rewrite formally" action and sets its reasoning effort to `high`. Another user sets a specific temperature. The editor shows "Automatic" by default, offers the values that the action's provider understands, and shows what "Automatic" means for the current model when it has a profile.

**Why this priority**: The automatic behavior covers the common case. The override is an escape hatch for specific needs and for a profile that turns out to be wrong.

**Independent Test**: In Settings, set an action's reasoning effort to `high`, save, run it, and confirm the request carries `high` in the provider's own parameter; set it back to "Automatic" and confirm the profile's value is used again.

**Acceptance Scenarios**:

1. **Given** the action editor is open, **When** the user leaves both settings on "Automatic" and saves, **Then** the action is stored without either value.
2. **Given** the user sets a reasoning effort or a temperature and saves, **When** the action runs, **Then** the user's value is used instead of the profile's preference, unless the profile says the model does not accept it.
3. **Given** the selected model has a profile, **When** the editor shows the "Automatic" option, **Then** it also shows what Automatic resolves to for that model (for example "Automatic (none)").
4. **Given** a hand-edited reasoning effort that the editor does not list, **When** the user opens and saves the action without touching that field, **Then** the value is kept unchanged.

---

### Edge Cases

- The user's override conflicts with a documented limit in the model's profile (a temperature the model rejects or the provider says to remove, or a reasoning effort the model does not support): the value is not sent, and the editor tells the user that it does not apply to this model.
- The user's override is rejected by an OpenAI model without a profile: the adaptive fallback applies, because the alternative is a guaranteed failure. On Anthropic or Gemini, the provider's error is shown, as today.
- A model ID is a dated snapshot of a profiled model (for example `gpt-6-luna-2026-09-01`): it uses the same profile.
- A profiled model is deprecated and silently routed by the provider to its successor (for example `gemini-3.5-flash`): the profile describes the model that actually answers.
- Two different parameters are rejected one after the other in the same OpenAI run: each is dropped once, so one run sends at most one adaptive retry per droppable parameter.
- The adaptive retry also fails for a transient reason (timeout, 5xx): the existing single transient retry rules apply unchanged; the two retry kinds do not combine into an unbounded loop.
- A hand-edited action has no `temperature` key, a `null` value, or a wrong-typed value: it is treated as "Automatic"; a wrong type is reported in the existing launch warning by key and action id, never by value. The same applies to `reasoningEffort`, where an empty or whitespace-only value also means "Automatic".
- The action's provider kind changes after a reasoning effort was set: the stored value is kept; if the new provider does not understand it, the editor warns and a profiled model does not receive it.
- The user changes the provider's model or base URL: rules learned for the old provider and model do not apply to the new one.

## Requirements *(mandatory)*

### Functional Requirements

**Built-in model profiles**

- **FR-001**: Overtype MUST ship built-in model profiles for the OpenAI-compatible, Anthropic and Gemini providers. A profile records, per model: the provider's reasoning parameter and the values the model supports, whether the model accepts a temperature (and under which reasoning value), and the reasoning value Overtype prefers. Overtype prefers the lowest latency that the model supports, because it rewrites text while the user waits.
- **FR-002**: The reasoning parameter is provider-native: `reasoning_effort` for OpenAI, `output_config.effort` for Anthropic, and for Gemini either `thinkingLevel` or `thinkingBudget`, as the model's profile records. Overtype MUST NOT send both Gemini parameters in one request.
- **FR-003**: The initial profiles MUST cover at least: the OpenAI GPT-6 family (`gpt-6-luna`, `gpt-6-sol`, `gpt-6-astra`, `gpt-6.1-sol`); the Claude models listed in Anthropic's effort documentation; the current Gemini 3.x and 4 text models and the Gemini 2.5 text models; and every model named in Overtype's seeded configuration and documentation recipes. Each profile MUST record the documentation source and date it is based on, and model IDs MUST be checked against the providers' deprecation pages.
- **FR-004**: A model MUST match a profile when its ID equals the profile's model ID or is a dated snapshot of it.
- **FR-005**: Profiles MUST be part of Overtype itself, updated with releases. The end user MUST NOT need to edit them or know they exist. Ollama has no profiles: Ollama applies generation options itself, and its models are the user's own.

**Request building**

- **FR-006**: The effective reasoning value MUST be the action's override if set, otherwise the profile's preferred value if the model has a profile, otherwise none (no reasoning parameter sent).
- **FR-007**: The effective temperature MUST be the action's override if set, otherwise none (the model's own default).
- **FR-008**: A value MUST NOT be sent when the model's profile says the model rejects it or the provider's documentation tells clients to remove it, even when the action sets it. This covers a temperature at a reasoning value that excludes it (OpenAI), any temperature on Gemini 3.x and 4, and a reasoning value the model does not support.
- **FR-009**: For a model without a profile, Overtype MUST send exactly the parameters the action sets and nothing else, so every model that works today gets the same request as before.
- **FR-010**: Anthropic MUST keep omitting temperature in all cases (feature 007). Ollama MUST NOT receive a reasoning value, and MUST receive a temperature only when the action sets one.

**Adaptive fallback (OpenAI only)**

- **FR-011**: When the OpenAI-compatible provider rejects a request with HTTP 400 and the structured error identifies a parameter that Overtype sent and is allowed to drop (`temperature` or `reasoning_effort`), Overtype MUST retry once without that parameter.
- **FR-012**: Overtype MUST remember a dropped parameter for that provider, base URL and model for the rest of the app session, and MUST NOT send it in later runs.
- **FR-013**: The adaptive fallback MUST NOT apply to any other error, MUST be cancellable, MUST show the existing retry feedback, and MUST NOT change the existing transient retry rules.
- **FR-014**: Before the fallback is relied on, a recorded diagnostic run MUST confirm that OpenAI's structured error names the rejected parameter for both `temperature` and `reasoning_effort` (Principle III).
- **FR-015**: The fallback MUST NOT apply to Anthropic or Gemini.
- **FR-016**: Overtype MUST identify a rejected parameter from a structured error field only, never by matching error message text. A dropped parameter MAY be logged by parameter name, provider id and model; the error message, which can echo submitted text, MUST NOT be logged at `info` level or above.

**Defaults**

- **FR-017**: The seeded configuration MUST use `gpt-6-luna` as the OpenAI provider's default model, and its seeded action MUST use "Automatic" for both settings.
- **FR-018**: When the user adds a new provider of the OpenAI kind in Settings, the default model field MUST be pre-filled with `gpt-6-luna`, and the user MUST be able to replace it.
- **FR-019**: An existing provider's default model and an action's model MUST NOT be changed by an upgrade.

**Configuration and editor**

- **FR-020**: An action's temperature and reasoning effort MUST both be optional; absent means "Automatic". Saving "Automatic" MUST leave the key out of the configuration file.
- **FR-021**: Configuration files written before this feature MUST load without loss; a stored temperature becomes the action's override and is kept in the file (FR-008 can still prevent it from being sent).
- **FR-022**: The action editor MUST offer "Automatic" or a specific temperature (0.0 to 2.0). For reasoning effort, it MUST offer "Automatic" or one of the values of the action's provider kind: OpenAI `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`; Anthropic `low`, `medium`, `high`, `xhigh`, `max`; Gemini `minimal`, `low`, `medium`, `high`. The value is passed to the provider unchanged. The editor MUST keep and display a hand-edited value that is not in the list, and MUST NOT offer reasoning effort for Ollama.
- **FR-023**: When the selected model has a profile, the editor MUST show what "Automatic" resolves to, and MUST warn when an override will not be sent under FR-008.
- **FR-024**: New actions MUST default to "Automatic" for both settings.

**Verification and documentation**

- **FR-025**: Profile lookup, effective-parameter resolution, request-body construction for every provider, and the decision whether an error allows an adaptive retry MUST be pure logic covered by unit tests.
- **FR-026**: The reason for each omitted or dropped parameter MUST be recorded in the code where it happens, so the behavior is not "simplified" later.
- **FR-027**: User-facing documentation MUST describe "Automatic", the override, the new OpenAI default model, and that Overtype adapts to OpenAI models it does not know. Documentation recipes MUST use models that have profiles and are not deprecated.

### Key Entities

- **Model profile**: Overtype's built-in knowledge about one model of one provider: the reasoning parameter and supported values, the temperature rule, the preferred reasoning value, and the documentation source and date.
- **Action override**: an optional temperature (0.0 to 2.0) and an optional reasoning effort (provider-native text) on an action. Absent means "Automatic".
- **Learned rejection**: a parameter that a specific OpenAI-compatible provider, base URL and model rejected during the current app session. It is held in memory only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A configuration that worked before this feature, with only the model changed to `gpt-6-luna`, runs successfully on the first request, with no change to any other setting.
- **SC-002**: A fresh install runs the seeded "Fix grammar" action against `gpt-6-luna` successfully with only an API key added.
- **SC-003**: For an OpenAI model with no profile that rejects `temperature`, the first run succeeds with exactly one extra request, and every later run in the same session sends exactly one request.
- **SC-004**: For models without a profile, on every provider, 100% of the requests built after the upgrade are identical to the requests built before it.
- **SC-005**: For every model in the initial profiles, a run with both settings on "Automatic" succeeds on the first request. For each provider, on one representative profiled model, the median time of five "Automatic" runs on the same text is lower than the median of five runs at the provider's default reasoning level.
- **SC-006**: Requests to Ollama never contain a reasoning value, and requests to Anthropic never contain a temperature, in 100% of unit-tested cases.

## Assumptions

- The OpenAI Models API reports no parameter support. Anthropic's and Gemini's report only part of what Overtype needs (see Clarifications). Profiles are therefore built in for all three.
- Learned rejections are kept in memory only. One extra request per OpenAI model after each app launch is an acceptable cost, and a wrong learned rule cannot persist.
- Profiles match by model ID, whatever the provider's base URL is. A compatible service that uses a different ID for the same model gets no profile.
- Part of the `gpt-6-luna` profile is inferred, not stated: OpenAI says to remove `temperature` "when reasoning effort is not `none`", which implies that `gpt-6-luna` accepts it at `none`. The SC-001 acceptance run confirms this; if it is wrong, the profile is corrected, and the fallback keeps runs working meanwhile. Every profile's content is treated as a claim to verify, as in FR-014.
- The meaning of a missing `temperature` key changes from 0.0 to "Automatic". The app and the previous seeded configuration always wrote the key, so only hand-written configurations without it are affected.
- Profiles change requests for existing, working Anthropic and Gemini configurations on profiled models (a lower reasoning level, and no temperature on Gemini 3.x and 4). This is the intended effect of "the project knows"; SC-004 covers only models without a profile.
- Overtype sends no `top_p`, `top_k`, `top_logprobs` or `logprobs` today, so the other sampling parameters in the providers' guidance need no handling.
- No new network endpoint, no clipboard use, and no logging of selected text or model output are introduced. The adaptive retry is a second request to the same provider before any write, so the selection stays untouched (Principle II).
- The SC-001, SC-002, SC-003 and SC-005 acceptance runs and the FR-014 diagnostic run use the user's own provider accounts and are recorded in `docs/compatibility.md`.
