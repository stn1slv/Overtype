# Implementation Plan: Local Ollama Model Support

**Branch**: `008-ollama-provider` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-ollama-provider/spec.md`

## Summary

Make the existing but non-functional `ollama` provider kind actually work, by
adding a dedicated provider that calls Ollama's own chat endpoint
(`POST /api/chat`, `stream: false`) against a service on the user's machine.
This is the fourth backend and the first that is not a cloud service, which is
what makes it more than a copy of feature 007: there is no credential in the
normal case, the endpoint is cleartext loopback, and the failures that matter
are local setup problems rather than API errors.

Cost against the constitution's extension model: one new `AIProvider` type
(`OllamaProvider`), one line in `ProviderRegistry`, and **no** new enum case —
`ProviderKind.ollama` already exists. Beyond that the feature touches three
things 007 did not:

1. **Three new `ProviderError` cases** — `serviceUnreachable(address:)`,
   `modelNotAvailable(model:)` and `inputTooLargeForContext(limit:)`, all
   permanent — because the failures a local backend introduces have no honest
   mapping onto the existing cases and Principle VI forbids putting the cause in
   a string.
2. **`Info.plist`, conditionally** — only if the built bundle turns out to block
   cleartext loopback. The planning probe suggests it does not; the decision is
   deferred to evidence rather than guessed (R9).
3. **A fixed `num_ctx`, plus a pre-send size refusal** — because when a prompt
   overflows the context window the service silently drops the oldest part, and
   rewriting a truncated selection over the whole selection destroys the user's
   text. The fixed window covers the default action limit; FR-010b closes the
   remaining hole by refusing, before sending anything, a selection larger than
   that window can safely hold.

Five decisions from the two clarification sessions shape the request: read only
`message.content` and never `message.thinking`, plus strip a leading
`<think>…</think>` block (reasoning must never reach the document); send
`temperature` (unlike Anthropic — Ollama accepts it uniformly); send
`num_ctx: 16384` with a 6000-character pre-send bound; send nothing about `keep_alive`; never require a credential.
Default model is `llama3.2` with a 30-second time limit; the shipped default
config is unchanged.

## Technical Context

**Language/Version**: Swift 5.9

**Primary Dependencies**: `URLSession` (async/await) for networking; existing
`KeychainStore`, `ResponseSanitizer`, `ProviderRegistry`, `ActionEngine`, and
`OpenAICompatibleProvider.extractErrorMessage(from:)` as a fallback. No new
third-party dependency.

**Storage**: `~/Library/Application Support/Overtype/config.json` (provider
record) and, optionally, the macOS Keychain. Neither schema changes; see
`data-model.md`.

**Testing**: XCTest via `swift test` for pure logic (request body construction,
response parsing, reasoning stripping, error extraction and mapping, endpoint
construction, retry classification of the three new cases, config decode).
System-boundary behaviour (a real HTTP call to a running Ollama, the ATS check
from the bundle, the offline run) is verified by the manual acceptance procedure
in `quickstart.md` and recorded in `docs/compatibility.md`.

> `swift test` requires the Xcode toolchain. With Command Line Tools active it
> fails with `no such module 'XCTest'`; prefix with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Target Platform**: macOS 13+ menu bar accessory (no Dock icon). The Ollama
service is a separate process on the user's machine, installed and run by them.

**Project Type**: Single native macOS app (Swift Package Manager). SPM
auto-globs sources, so the new provider file needs no `Package.swift` edit.

**Performance Goals**: One request/response per run, no streaming. Honors the
per-provider hard timeout and Escape cancellation. Local inference is slower and
far more variable than a cloud call, and the first request after an idle period
also pays model load time; the feature does not hide this, it documents it and
lets the existing time limit bound it.

**Constraints**: No clipboard. No endpoint other than the provider's configured
one. No secret, selected text, or model output in logs at `info` or above. Force
unwrapping forbidden except commented Core Foundation casts (none expected
here). Cleartext `http://` to loopback must work (FR-008).

**Scale/Scope**: Small. One new provider file (~400 lines, larger than
`AnthropicProvider` because of the transport-error mapping and the reasoning
strip), three new error cases with their three switch arms, one registry line,
four small edits in one Settings view, a new test file, and doc updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Clipboard Isolation (NON-NEGOTIABLE)**: PASS. The feature adds a network
  provider, three error cases, and picker entries. No `NSPasteboard` use;
  `rg NSPasteboard Sources/` stays clean.
- **II. Non-Destructive by Default (NON-NEGOTIABLE)**: PASS, and strengthened.
  `OllamaProvider` only returns text into the existing pipeline; the
  frontmost-app / pid / focused-element re-check before writing is unchanged, and
  every Ollama failure — including all three new error cases and a reasoning-only
  response — throws before any write. The feature also **closes** a
  local-specific destruction path that would otherwise exist: without a fixed
  `num_ctx`, an oversized prompt is silently shortened by the service and the
  resulting partial rewrite would be written over the full selection (R3).
- **III. Evidence Over Assumption**: PASS. This is an HTTP API rather than the
  Accessibility boundary, so the rule applies in its documentary form: the wire
  contract is taken from Ollama's published reference and captured in
  `contracts/ollama-chat.md` rather than assumed. Where the platform, not the
  API, is in question — whether App Transport Security blocks cleartext loopback
  from the bundle — the plan **refuses to guess**: R9 records an actual probe
  (`-1004`, not `-1022`), states plainly that a script probe is not evidence
  about the bundle, and defers the Info.plist decision to acceptance item O6.
  The three non-obvious request choices (`stream: false`, sending `temperature`
  where Anthropic does not, `num_ctx`) and both reasoning layers each carry an
  inline comment naming the reason, so they cannot be "simplified" away without
  fresh evidence.
- **IV. Configuration Over Code**: **PASS for the user-facing promise; the
  code-side allowance is exceeded by two files, and both are recorded below as
  explicit dated exceptions** under the Governance clause "Any deviation found
  MUST be either corrected or recorded as an explicit, dated exception in the
  plan that introduced it." A cross-artifact analysis on 2026-08-06 raised this
  as a CRITICAL finding; the exceptions below are the response, and they are
  recorded rather than argued away.

  Enabling Ollama for a user is pure configuration: a provider block, or a
  Settings picker selection, with no credential at all. That half of the
  principle is satisfied outright. Adding the *backend* costs one new
  `AIProvider` type and one `ProviderRegistry` line — below the three permitted
  edits, because `ProviderKind.ollama` already exists. The principle's "No other
  file may need to change" is what is exceeded.

  **Exception IV-a, dated 2026-08-06 — `UI/Settings/ProvidersTab.swift`
  (4 edits).**
  - *Why it cannot be avoided*: FR-002 requires Ollama to be selectable in
    Settings without a "not implemented" qualifier, and FR-005 requires the key
    field to read as optional. `selectableKinds` is a hardcoded allow-list and
    `kindLabel(_:)` an exhaustive switch, so *every* backend already requires an
    edit here — Gemini and Anthropic both did.
  - *Scope of the deviation*: three of the four edits correct statements this
    feature makes false; only the optional-key prompt is new behaviour. The
    provider is fully functional through `config.json` with none of them, so US1
    does not depend on this file.
  - *Simpler alternative rejected*: dropping FR-002 and shipping a
    config-file-only backend. Rejected because a working backend that the UI
    actively denies is a worse outcome than the deviation.
  - *Debt*: the principle predates the settings GUI (feature 003) and has never
    been reconciled with it. The remedy is a constitution amendment recording
    the `selectableKinds` allow-list as a Known Deviation, alongside the six
    already listed there. **This plan does not perform that amendment**;
    Governance requires amendments to be a separate, explicit change.

  **Exception IV-b, dated 2026-08-06 — `Providers/AIProvider.swift`
  (3 new `ProviderError` cases + their 3 switch arms).**
  - *Why it cannot be avoided*: the constitution's "no other file may need to
    change" assumes a new backend introduces no new *kind* of failure. A local
    backend introduces three: the service is not running, the model was never
    downloaded, and the selection cannot fit the context window. Principle VI
    requires these to be typed values rather than strings, so they must exist
    somewhere.
  - *Simpler alternative evaluated and rejected — a provider-local error type.*
    Swift's `throws` is untyped, so `OllamaProvider` could declare its own
    `OllamaError` and leave `AIProvider.swift` untouched, satisfying Principle
    IV literally. It was rejected on three concrete grounds, not on taste:
    1. `ActionEngine.transformWithRetry` gates retries on
       `(error as? ProviderError)?.isRetryable`. A foreign error type is not a
       `ProviderError`, so it would fall through the classification entirely —
       exactly the "cause lives outside the type system" outcome Principle VI
       forbids, and clarification 4 rejected.
    2. `FeedbackPresenter` and `ActionEngine` present failures through
       `ProviderError`; a second error type means a second presentation path,
       which is more shared-surface change than the three additive cases, not
       less.
    3. It satisfies the letter of Principle IV while defeating its purpose. The
       principle exists so backends stay cheap to add, not so a shared type stays
       frozen at the cost of duplicated error handling.
  - *Scope of the deviation*: purely additive. All three cases are
    permanent-classified and `retryableURLErrorCodes` is untouched, so no
    existing provider's behaviour changes. Existing exhaustive switches fail to
    compile until each case is handled, which is the intended safety property.
  - *Debt*: none carried forward. This is a one-time widening of the shared
    error vocabulary that any future local-execution backend would reuse.

  Both exceptions are additive, neither introduces new coupling, and both are
  listed in Complexity Tracking below rather than left implicit.
- **V. Privacy and Secret Handling (NON-NEGOTIABLE)**: PASS, and this feature is
  the principle's own stated motivation ("The support for local models through
  Ollama exists precisely so that this can be avoided entirely"). A credential
  is optional; when present it is read from the Keychain and sent in an
  `Authorization` header, never in the URL, never written to config,
  `UserDefaults`, logs, error messages, or the UI. Selected text and output are
  logged only via `sanitizedLog()` at debug. Failures are logged via
  `logLabel`, and the two new labels carry no payload. The typed payloads that
  *are* shown to the user (address, model name) both come from the user's own
  configuration, never from server-authored text. The only endpoint contacted is
  the configured one, which in the documented setup is the user's own machine —
  and SC-004 requires the run to succeed with every network interface off, which
  is a stronger check on "no telemetry" than any previous feature has had.
- **VI. No Silent Failure**: PASS. Every outcome maps to a specific typed error;
  the three failures unique to a local backend get their own cases rather than
  collapsing into a generic network error, and are classified permanent so the
  user sees the real cause immediately instead of after a pointless retry. A
  response that is nothing but reasoning becomes `.emptyResponse` rather than
  writing scratch work. Existing HUD feedback, Escape cancellation, and the hard
  timeout apply unchanged.
- **VII. Native Stack, Minimal Dependencies**: PASS. Swift 5.9, `URLSession`,
  SwiftUI unchanged. No new dependency. No force unwraps introduced — the default
  base URL is held as a `String`, matching `GeminiProvider` and
  `AnthropicProvider`. The error-message extractor chains to the existing one
  rather than duplicating its fallback. If O6 forces an Info.plist change, the
  narrow `NSAllowsLocalNetworking` is used and `NSAllowsArbitraryLoads` is
  rejected outright.
- **VIII. Verification Discipline**: PASS. Pure logic gets unit tests, including
  both reasoning layers and the retry classification of the two new cases. The
  real HTTP boundary, the ATS behaviour of the bundle, and the offline run get
  the manual acceptance procedure in `quickstart.md`, not mocks that assert on
  themselves. One honest limit is recorded there: acceptance item O12 (a real
  model that emits reasoning) needs a second model pulled, and if it is not, O12
  must be recorded as *not executed* rather than as passed.

Two recorded exceptions (IV-a, IV-b), both tabulated in Complexity Tracking. No
other principle is deviated from.

**Post-Design Re-check (after Phase 1)**: PASS. The design artifacts introduce
no new third-party dependency, no clipboard path, and no persisted schema change
— `data-model.md` confirms `AppConfig.swift` and `DefaultConfig.swift` are
untouched. Phase 0 changed the shape of the work in three ways, all recorded:
R6 established that new error cases *are* required (unlike 007, where none
were), which is why Principle IV now names a second file; R8 found a real trap
that would have broken FR-005 had `AnthropicProvider`'s credential guard been
copied — a provider created in Settings with an empty key field still has a
`keychainKey`, so key presence must not be read as key required; and R9 replaced
an assumption about ATS with a probe plus a deferred, evidence-gated decision.
Principle II is strengthened rather than merely preserved, because R3 closes a
truncation path that the other providers do not have.

**Post-Analysis Revision (2026-08-06)**: a cross-artifact analysis raised one
CRITICAL and one HIGH finding, both now resolved in the artifacts rather than
waived. The CRITICAL finding (Principle IV allowance exceeded) is answered by
Exceptions IV-a and IV-b above, which additionally evaluate the provider-local
error type alternative that the first draft of this plan never weighed. The HIGH
finding (FR-010a promised more than the design delivered) is answered by the new
FR-010b, which costs a third `ProviderError` case and a pre-send size check;
this *widens* Exception IV-b by one case while *closing* a path in which the
user's text could be silently lost, which is the correct trade under Principle
II. No gate changed to a failing state.

## Project Structure

### Documentation (this feature)

```text
specs/008-ollama-provider/
├── plan.md              # This file
├── spec.md              # From /speckit-specify + two /speckit-clarify sessions
├── research.md          # Phase 0 output (R1-R12)
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output (acceptance O1-O16)
├── contracts/
│   └── ollama-chat.md   # POST /api/chat request/response contract
└── checklists/
    └── requirements.md  # From /speckit-specify + /speckit-clarify
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Config/
│   ├── AppConfig.swift              # UNCHANGED: ProviderKind.ollama already exists
│   └── DefaultConfig.swift          # UNCHANGED: shipped default config not seeded
├── Providers/
│   ├── AIProvider.swift             # EDIT (Exception IV-b): +3 ProviderError cases, +3 switch arms
│   ├── OllamaProvider.swift         # NEW: AIProvider conformance calling /api/chat
│   ├── AnthropicProvider.swift      # unchanged (structural template)
│   ├── GeminiProvider.swift         # unchanged
│   ├── OpenAICompatibleProvider.swift   # unchanged (extractErrorMessage chained to)
│   └── ProviderRegistry.swift       # EDIT: one line — case .ollama: OllamaProvider(config:)
├── Resources/
│   └── Info.plist                   # CONDITIONAL EDIT: NSAllowsLocalNetworking, only if O6 fails
└── UI/Settings/
    └── ProvidersTab.swift           # EDIT (Exception IV-a): selectableKinds, kindLabel, placeholder, key-field prompt

Tests/OvertypeTests/
├── OllamaProviderTests.swift        # NEW: request body, parsing, reasoning strip,
│                                    #      error extraction/mapping, endpoint URL
├── TransformRetryTests.swift        # EDIT: assert both new cases are non-retryable
└── AppConfigTests.swift             # EDIT: Ollama ProviderConfig decode, keyless + no baseURL

docs/
├── compatibility.md                 # EDIT: Ollama manual acceptance section (O1-O16)
└── privacy.md                       # EDIT: Ollama as a destination; local-only phrasing

README.md                            # EDIT: Ollama recipe; drop "coming soon" from line 10
```

**Structure Decision**: Single-project native app; the feature slots into the
existing `Sources/Overtype/Providers/` layer beside `AnthropicProvider` and
mirrors its structure — an ephemeral `URLSession` configured from
`timeoutSeconds`, a `String` default base URL, and pure logic split into `static`
helpers so it is unit-testable without a network. No new module or directory.

Two structural differences from the Anthropic template, both forced by this being
a local backend rather than stylistic:

1. **Transport errors are inspected, not just mapped.** `AnthropicProvider`
   delegates every transport failure to `ProviderError.mapTransportError`.
   `OllamaProvider` first checks for the connection-refused family and turns it
   into `serviceUnreachable(address:)`, delegating everything else. This is the
   only place any provider overrides the shared transport mapping, and it is
   confined to this provider so the other three keep their current retry
   behaviour.
2. **No credential guard.** Where `AnthropicProvider` opens with
   `guard let keychainKey … else { throw .apiKeyMissing }`, this provider must
   not — see R8. That absence is the single most likely thing for a future reader
   to "fix", so it carries a comment naming the Settings behaviour that makes it
   necessary.

## Complexity Tracking

Two recorded exceptions to Principle IV's "No other file may need to change",
both dated 2026-08-06 and detailed in the Constitution Check above.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| IV-a: `UI/Settings/ProvidersTab.swift` edited (4 changes) | FR-002 requires Ollama to be selectable without a "not implemented" label; FR-005 requires the key field to read as optional. `selectableKinds` and `kindLabel(_:)` are a hardcoded allow-list and an exhaustive switch that every backend already has to touch | Dropping FR-002 and shipping a config-file-only backend would leave the UI actively denying a working provider, which is worse than the deviation. The provider itself needs none of these edits |
| IV-b: `Providers/AIProvider.swift` edited (3 new `ProviderError` cases) | A local backend introduces three failure kinds no cloud provider has: service not running, model not downloaded, selection too large for the context window. Principle VI requires them to be typed values | A provider-local `OllamaError` would satisfy Principle IV literally but bypass `ActionEngine.transformWithRetry`'s `isRetryable` classification and force a second error-presentation path — more shared-surface change, not less, and it defeats the purpose the principle exists for |
