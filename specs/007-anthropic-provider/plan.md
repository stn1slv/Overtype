# Implementation Plan: Anthropic Claude Model Support

**Branch**: `007-anthropic-provider` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-anthropic-provider/spec.md`

## Summary

Make the existing but non-functional `anthropic` provider kind actually work, by
adding a dedicated native provider that calls Anthropic's Messages API
(`POST /v1/messages`). This follows the constitution's extension model, and costs
*less* than the three permitted edits: one new type conforming to `AIProvider`
(`AnthropicProvider`) and one line in `ProviderRegistry`. **No enum case is
needed — `ProviderKind.anthropic` already exists — and no new `ProviderError`
case is needed either, because `responseBlocked(reason:)` and `emptyResponse`
were both added by 004.** `Sources/Overtype/Providers/AIProvider.swift` and
`Sources/Overtype/Config/AppConfig.swift` are therefore untouched.

Beyond the provider, this feature does one thing 004 did not: it fixes the
Settings Providers tab, where Anthropic is currently hidden from the kind picker
and labelled "(not implemented)".

Three decisions from the clarification session shape the request body. The API
key is read from the Keychain and sent in `x-api-key`, never in a URL. A required
`max_tokens` is supplied as a fixed constant (8192) because no config field
expresses one. The action's `temperature` is **never sent**, because current
Claude models reject it with HTTP 400. Response `content` is an array of typed
blocks, and only `text` blocks are used — reasoning blocks must never reach the
user's document. Default model is `claude-haiku-4-5`; the shipped default config
is unchanged.

## Technical Context

**Language/Version**: Swift 5.9

**Primary Dependencies**: `URLSession` (async/await) for networking; existing
`KeychainStore`, `ResponseSanitizer`, `ProviderRegistry`, `ActionEngine`, and
`OpenAICompatibleProvider.extractErrorMessage(from:)`. No new third-party
dependency.

**Storage**: `~/Library/Application Support/Overtype/config.json` (provider
record) and macOS Keychain (API key). Both already exist; neither schema changes.

**Testing**: XCTest via `swift test` for pure logic (response parsing, reasoning
filtering, error mapping, endpoint construction, config decode). System-boundary
behavior (a real HTTP call to Anthropic) verified by a manual acceptance
procedure recorded in `docs/compatibility.md`.

> Note: `swift test` requires the Xcode toolchain. With Command Line Tools
> active it fails with `no such module 'XCTest'`; prefix with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Target Platform**: macOS 13+ menu bar accessory (no Dock icon).

**Project Type**: Single native macOS app (Swift Package Manager). SPM
auto-globs sources, so the new provider file needs no `Package.swift` edit.

**Performance Goals**: One request/response per run, no streaming. Honors the
existing per-provider hard timeout (`ProviderConfig.timeoutSeconds`, default 30s)
and Escape-key cancellation. `max_tokens` is held at 8192, below the size at
which a non-streaming request risks a transport timeout.

**Constraints**: No clipboard. No network endpoint other than the Anthropic
service. No secret, selected text, or model output in logs at `info` or above.
Force unwrapping forbidden except commented Core Foundation casts (none expected
here).

**Scale/Scope**: Small. One new provider file (~130 lines), one registry line,
three small edits in one Settings view, unit tests, and doc updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Clipboard Isolation (NON-NEGOTIABLE)**: PASS. The feature adds a network
  provider and a picker entry only. No `NSPasteboard` use; `rg NSPasteboard
  Sources/` stays clean.
- **II. Non-Destructive by Default (NON-NEGOTIABLE)**: PASS. `AnthropicProvider`
  only returns text into the existing pipeline. The frontmost-app / pid /
  focused-element re-check in `ActionEngine` before writing is unchanged, and
  every Anthropic failure — including a missing Keychain key, which is detected
  before any request is sent — throws before any write.
- **III. Evidence Over Assumption**: PASS (with note). This is an HTTP API, not
  the Accessibility/synthetic-event boundary, so the empirical-verification rule
  applies in its documentary form: the wire contract is taken from Anthropic's
  published Messages API reference (captured in `research.md` and `contracts/`)
  rather than assumed, and a manual acceptance procedure exercises a real call,
  the refusal path, and the reasoning-filter path before release. The two
  non-obvious omissions (`temperature`, and any `thinking`/`effort` field) each
  carry an inline comment naming the reason, so they are not "simplified" back in
  without fresh evidence — the same discipline the constitution requires of
  boundary workarounds.
- **IV. Configuration Over Code**: PASS, with a documented caveat. Enabling
  Anthropic for a user is pure configuration (a provider block + a Keychain key)
  or a Settings picker selection. Adding the *backend* costs one new `AIProvider`
  type and one `ProviderRegistry` line — below the three permitted edits, because
  the `ProviderKind` case already exists.

  **Caveat, stated plainly**: this feature also edits a fourth file,
  `UI/Settings/ProvidersTab.swift`, which the principle's "No other file may need
  to change" does not literally allow. Three things justify it rather than
  excusing it:
  1. It is **not backend plumbing**. The provider is fully functional through
     `config.json` without this edit; US1 does not depend on it. The edit exists
     solely to satisfy FR-002.
  2. It **corrects pre-existing stale UI**, it does not add new coupling. That
     file already carries an `.anthropic` label reading "(not implemented)" —
     a statement this feature makes false. Shipping a working backend that the UI
     actively denies is the worse outcome.
  3. The coupling is **pre-existing and not introduced here**. `selectableKinds`
     is a hardcoded allow-list (`[.openAICompatible, .gemini]`) and
     `kindLabel(_:)` is an exhaustive switch, so *every* backend already requires
     an edit there — Gemini included. The principle was written before the
     settings GUI (003) existed and has not been reconciled with it.

  Because the constraint is structural rather than specific to this feature, the
  right remedy is not to contort this plan: it is to record the
  `ProvidersTab.selectableKinds` allow-list as a **Known Deviation** candidate in
  a future constitution amendment, alongside the deviations already listed there.
  This plan flags it rather than silently passing the gate.

  Model resolution reuses the existing action-model-then-provider-default order,
  so no action-side change is needed.
- **V. Privacy and Secret Handling (NON-NEGOTIABLE)**: PASS. The key is read from
  the Keychain and passed in the `x-api-key` header; the request URL carries no
  query string at all. It is never written to config, `UserDefaults`, logs, error
  messages, or UI. Selected text and output are logged only via `sanitizedLog()`
  at debug. Failures are logged via `ProviderError.logLabel` (`"HTTP 401"`), never
  `errorDescription`, which embeds the server message. `stop_details.explanation`
  is deliberately discarded for the same reason. The only endpoint contacted is
  the Anthropic service.
- **VI. No Silent Failure**: PASS. Every outcome maps to a specific typed
  `ProviderError` — a declined response and an empty response are distinguished,
  and any non-normal `stop_reason` is reported by name rather than collapsing to
  an empty result. Existing HUD feedback, Escape cancellation, hard timeout, and
  the single automatic retry apply unchanged.
- **VII. Native Stack, Minimal Dependencies**: PASS. Swift 5.9, `URLSession`,
  SwiftUI unchanged. No new dependency. No force unwraps introduced — the default
  base URL is held as a `String`, not a force-unwrapped `URL`, matching
  `GeminiProvider`. The error-message extractor is reused rather than duplicated.
- **VIII. Verification Discipline**: PASS. Pure logic (parsing, reasoning
  filtering, error mapping, endpoint construction, config decode) gets unit
  tests; the real HTTP boundary gets a manual acceptance procedure, not a mock
  that asserts on itself.

No violations. Complexity Tracking is empty.

**Post-Design Re-check (after Phase 1)**: PASS. The design artifacts introduce no
new third-party dependency, no clipboard path, and no new persisted schema —
`data-model.md` confirms zero changes to `AppConfig.swift`, including the
`ProviderKind` enum. Phase 0 further *reduced* the footprint versus the initial
estimate: research R6 established that no new `ProviderError` case is required,
so `AIProvider.swift` is untouched and FR-011 (retry classification) costs no
code at all, because `isRetryable` already routes 429 and 529 correctly. The one
scope addition over 004 is the Settings picker fix (research R10), required by
FR-002 and confined to three small edits in a single view. Principle V is
strengthened rather than weakened by the design: the contract explicitly discards
`stop_details.explanation`. No gate changed.

## Project Structure

### Documentation (this feature)

```text
specs/007-anthropic-provider/
├── plan.md              # This file
├── spec.md              # From /speckit-specify + /speckit-clarify
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── anthropic-messages.md   # Anthropic Messages API request/response contract
└── checklists/
    └── requirements.md  # From /speckit-specify + /speckit-clarify
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Config/
│   ├── AppConfig.swift              # UNCHANGED: ProviderKind.anthropic already exists
│   └── DefaultConfig.swift          # UNCHANGED: shipped default config not seeded
├── Providers/
│   ├── AIProvider.swift             # UNCHANGED: needed ProviderError cases already exist
│   ├── AnthropicProvider.swift      # NEW: AIProvider conformance calling /v1/messages
│   ├── GeminiProvider.swift         # unchanged (structural template)
│   ├── OpenAICompatibleProvider.swift   # unchanged (extractErrorMessage reused)
│   └── ProviderRegistry.swift       # EDIT: one line — case .anthropic: AnthropicProvider(config:)
└── UI/Settings/
    └── ProvidersTab.swift           # EDIT: selectableKinds, kindLabel, base-URL placeholder

Tests/OvertypeTests/
├── AnthropicProviderTests.swift     # NEW: pure-logic unit tests (parse, reasoning filter,
│                                    #      error mapping, endpoint URL)
└── AppConfigTests.swift             # EDIT: add Anthropic ProviderConfig decode test (US2)

docs/
├── compatibility.md                 # EDIT: add Anthropic manual acceptance section (A1–A10)
└── privacy.md                       # EDIT: note Anthropic endpoint as a data destination

README.md                            # EDIT: Anthropic recipe; drop "coming soon" claim
```

**Structure Decision**: Single-project native app; the feature slots into the
existing `Sources/Overtype/Providers/` layer beside `GeminiProvider` and mirrors
its structure — an ephemeral `URLSession` configured from `timeoutSeconds`, a
`String` default base URL, and the pure logic split into `static` helpers so it
is unit-testable without a network. No new module or directory beyond the one new
provider file and its test file.

The one structural simplification versus the Gemini template: because Anthropic
takes the model in the request body rather than the URL path,
`endpointURL(base:)` needs no model argument and none of the colon-escaping
workaround that `GeminiProvider.endpointURL(base:model:)` requires.

## Complexity Tracking

No constitution violations. No entries.
