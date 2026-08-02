# Implementation Plan: Gemini Model Support

**Branch**: `004-gemini-provider` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-gemini-provider/spec.md`

## Summary

Add Google Gemini as a first-class AI backend by introducing a dedicated native
provider that calls the Gemini `generateContent` REST API. This follows the
constitution's extension model exactly: one new `ProviderKind` case (`gemini`),
one new type conforming to `AIProvider` (`GeminiProvider`), and one line in
`ProviderRegistry`. Gemini-specific failures (safety blocks, empty candidates)
map to specific typed `ProviderError` values, so no run fails silently. The API
key is read from the Keychain and sent via the `x-goog-api-key` header; it never
appears in a URL, config, log, or the UI. The shipped default config is
unchanged; enabling Gemini is a documented configuration recipe. Default model
is `gemini-3.5-flash-lite`.

## Technical Context

**Language/Version**: Swift 5.9

**Primary Dependencies**: `URLSession` (async/await) for networking; existing
`KeychainStore`, `ResponseSanitizer`, `ProviderRegistry`, `ActionEngine`. No new
third-party dependency.

**Storage**: `~/Library/Application Support/Overtype/config.json` (provider
record) and macOS Keychain (API key). Both already exist.

**Testing**: XCTest via `swift test` for pure logic (response parsing, error
mapping, request-body building, prompt templating). System-boundary behavior (a
real HTTP call to Gemini) verified by a manual acceptance item recorded in
`docs/compatibility.md`.

**Target Platform**: macOS 13+ menu bar accessory (no Dock icon).

**Project Type**: Single native macOS app (Swift Package Manager).

**Performance Goals**: One request/response per run, no streaming. Honors the
existing per-provider hard timeout (`ProviderConfig.timeoutSeconds`, default 30s)
and Escape-key cancellation.

**Constraints**: No clipboard. No network endpoint other than the Gemini service.
No secret, selected text, or model output in logs at `info` or above. Force
unwrapping forbidden except commented Core Foundation casts (none expected here).

**Scale/Scope**: Small. One new provider file (~120 lines), a few new
`ProviderError` cases, one enum case, one registry line, unit tests, and doc
updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Clipboard Isolation (NON-NEGOTIABLE)**: PASS. The feature adds a network
  provider only. No `NSPasteboard` use; `rg NSPasteboard Sources/` stays clean.
- **II. Non-Destructive by Default (NON-NEGOTIABLE)**: PASS. `GeminiProvider`
  only returns text into the existing pipeline. The frontmost-app / pid /
  focused-element re-check in `ActionEngine` before writing is unchanged, and
  every Gemini failure throws before any write.
- **III. Evidence Over Assumption**: PASS (with note). This is an HTTP API, not
  the Accessibility/synthetic-event boundary. The wire contract is taken from
  Google's published `generateContent` reference (captured in `research.md` and
  `contracts/`), and a manual acceptance item exercises a real Gemini call and
  the safety-block path before release.
- **IV. Configuration Over Code**: PASS. Enabling Gemini for a user is pure
  configuration (a provider block + a Keychain key). Adding the backend costs
  exactly the three permitted edits: `ProviderKind.gemini`, `GeminiProvider`,
  one `ProviderRegistry` line. No action-side change needed; model resolution
  reuses the existing action-model-then-provider-default order.
- **V. Privacy and Secret Handling (NON-NEGOTIABLE)**: PASS. The key is read
  from the Keychain and passed in the `x-goog-api-key` header, never in the URL
  query string (which could be logged). It is never written to config,
  `UserDefaults`, logs, error messages, or UI. Selected text and output are
  logged only via `sanitizedLog()` at debug. The only endpoint contacted is the
  Gemini service.
- **VI. No Silent Failure**: PASS. New failure modes map to specific typed
  `ProviderError` cases (blocked response with reason; empty response). Existing
  HUD feedback, Escape cancellation, and hard timeout apply unchanged.
- **VII. Native Stack, Minimal Dependencies**: PASS. Swift 5.9, `URLSession`,
  SwiftUI unchanged. No new dependency. No force unwraps introduced.
- **VIII. Verification Discipline**: PASS. Pure logic gets unit tests; the real
  HTTP boundary gets a manual acceptance item, not a mock that asserts on itself.

No violations. Complexity Tracking is empty.

**Post-Design Re-check (after Phase 1)**: PASS. The design artifacts introduce no
new third-party dependency, no clipboard path, and no new persisted schema. The
two new `ProviderError` cases keep every failure typed and specific (Principle
VI), and the key stays in the `x-goog-api-key` header out of any URL (Principle
V). Edit count remains the three permitted by Principle IV (enum case, provider
type, registry line) plus tests and docs. No gate changed.

### Revision: Implementation Sync 2026-08-02

- Reason: Reconciled the Project Structure with the shipped implementation. The
  US2 config-decode test landed in the existing `Tests/OvertypeTests/AppConfigTests.swift`
  (alongside the other config decode tests) rather than in a new file, and the
  `GeminiProviderTests` coverage note was corrected to reflect the actual tests
  (parse, error mapping, endpoint URL construction). No code change; documentation
  accuracy only.

## Project Structure

### Documentation (this feature)

```text
specs/004-gemini-provider/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── gemini-generatecontent.md   # Gemini REST request/response contract
└── checklists/
    └── requirements.md  # From /speckit-specify + /speckit-clarify
```

### Source Code (repository root)

```text
Sources/Overtype/
├── Config/
│   └── AppConfig.swift              # EDIT: add `case gemini = "gemini"` to ProviderKind
├── Providers/
│   ├── AIProvider.swift             # EDIT: add ProviderError cases (responseBlocked, emptyResponse)
│   ├── GeminiProvider.swift         # NEW: AIProvider conformance calling generateContent
│   ├── OpenAICompatibleProvider.swift   # unchanged (reference pattern)
│   └── ProviderRegistry.swift       # EDIT: one line — case .gemini: GeminiProvider(config:)
└── ...

Tests/OvertypeTests/
├── GeminiProviderTests.swift        # NEW: pure-logic unit tests (parse, error mapping, endpoint URL)
└── AppConfigTests.swift             # EDIT: add Gemini ProviderConfig decode test (US2)

docs/
├── compatibility.md                 # EDIT: add Gemini manual acceptance results
└── privacy.md                       # EDIT: note Gemini endpoint as a data destination

README.md                            # EDIT: documented Gemini provider recipe
```

**Structure Decision**: Single-project native app; the feature slots into the
existing `Sources/Overtype/Providers/` layer beside `OpenAICompatibleProvider`
and follows its structure. No new module or directory beyond the one new
provider file and its test file.

## Complexity Tracking

No constitution violations. No entries.
