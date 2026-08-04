# Phase 0 Research: Application Version in Settings General Tab

**Feature**: `006-settings-version-display` | **Date**: 2026-08-04

No `NEEDS CLARIFICATION` markers were carried into this phase. The two open
questions from the spec were already settled by the clarification session (display
format, and build-time version stamping). What follows are the design decisions
needed to implement those answers, each with the alternatives that were rejected.

## Observed starting state

Facts established by inspecting the repository, not assumed:

| Fact | Evidence |
|------|----------|
| Newest release tag is `v1.2.1` | `git tag --sort=-v:refname \| head -1` |
| Bundle declares `1.1` / build `2` | `Sources/Overtype/Resources/Info.plist` lines 13-16 |
| Nothing writes the version at build time | `scripts/build-app.sh` copies `Info.plist` verbatim (line 20) |
| The release pipeline derives the version from the tag, but only for the zip name and the Homebrew cask | `.github/workflows/release.yml` lines 31, 38, 46 |
| Commit count is currently 20 | `git rev-list --count HEAD` |
| No pasteboard use anywhere in sources | `rg NSPasteboard Sources/` returns nothing |

So a user who installs release `1.2.1` today would be shown `1.1 (2)` by a naive
implementation. This is exactly the failure the clarification ruled out.

Note: the spec and its checklist say the newest release is `1.1.0`. That number
came from the archive Spec Kit extension's own version, not from the application.
The requirements are unaffected; only the concrete numbers differ.

## D1. Where the displayed version comes from at runtime

**Decision**: Read `CFBundleShortVersionString` and `CFBundleVersion` from
`Bundle.main.infoDictionary`.

**Rationale**: This is the value the operating system itself reports for the
installed application, so it is the same value Finder, the Homebrew cask and a
crash report would show. It requires no build-system plumbing inside the Swift
package, and it is automatically correct once the bundle is stamped (D4).

**Alternatives considered**:

- *Compile-time constant injected with `-D` or a generated Swift file*: would need
  a SwiftPM plugin or a code-generation step, adds a build dependency, and would
  still have to be kept in step with the plist that macOS actually reports.
  Rejected as more machinery for no extra accuracy.
- *Read the version from the git tag at runtime*: impossible in a shipped app, and
  it would be a filesystem/process call at display time. Rejected.

**Consequence**: under `swift test`, `Bundle.main` is the test runner, not the
app, so the bundle lookup itself cannot be unit-tested. This forces the split in
D7 and is the reason the formatting logic takes its two inputs as parameters.

## D2. Formatting and fallback rules

**Decision**: A pure function over two optional strings:

1. Trim whitespace from both inputs; treat empty-after-trim as absent.
2. Short version absent → `Unknown`.
3. Short version present, build absent → `<short version>`.
4. Both present → `<short version> (<build>)`.

**Rationale**: Rule 4 is the format fixed by the clarification (macOS convention,
`1.2.1 (20)`). Rule 2 implements FR-007: the released version is the piece that
gives the display its meaning, so if it is missing there is nothing honest to
show. Rule 3 avoids throwing away a usable answer over a missing build identifier
and never renders a stray empty `()`. Whitespace trimming exists because a plist
value of `" "` is a realistic hand-edit mistake and must be treated as absent, not
rendered as a blank version.

**Alternatives considered**:

- *`Unknown` whenever either value is missing*: simpler to state, but it discards
  a correct released version because a secondary identifier is absent. Rejected as
  less useful and less honest.
- *Render `1.2.1 ()` when the build is missing*: looks like a defect. Rejected.
- *Fall back to a hardcoded default version string in code*: would reintroduce
  exactly the duplicated, silently-stale value that FR-002 forbids. Rejected.

## D3. Placement and presentation on the General tab

**Decision**: A new `Section` at the end of the `Form` in `GeneralTab.swift`,
after the existing "Save Preferences" section, containing a single row: the label
`Version` followed by the formatted value with `.textSelection(.enabled)`.

**Rationale**: The spec's assumption places it at the end so it does not displace
the controls users interact with. A separate `Section` is the SwiftUI construct
that renders as its own group in a `Form`, which visually separates read-only
information from the editable fields (FR-006). `.textSelection(.enabled)` is the
native, focus-free way to satisfy FR-005, and copying is performed by the system
on the user's explicit command, so no application code touches the pasteboard.

**Alternatives considered**:

- *Add the row to the existing `Grid` at the top*: the Grid exists to align the
  editable settings labels; putting a read-only value in it would place version
  information above the controls and blur the read-only/editable distinction.
  Rejected.
- *`LabeledContent`*: available on macOS 13 and would work, but the file's
  established idiom is explicit `Text` + `HStack`/`Grid` layout. Introducing a
  second layout idiom for one row is unnecessary. Rejected on consistency grounds.
- *A separate "About Overtype" window or menu item*: explicitly out of scope in
  the spec's assumptions. Rejected.

**Reversed 2026-08-04, after code review**: the `HStack` was replaced by
`LabeledContent`, which fixes two concrete defects the original had: a long value
truncated instead of wrapping (paired here with
`.fixedSize(horizontal: false, vertical: true)`), and VoiceOver announced the
label and value as two unrelated elements. Two extra layout idioms in one file is
a smaller cost than two defects.

**Correction, same day, after a second review round**: the reversal was first
justified partly on the grounds that `LabeledContent` would align this label with
the trailing-aligned `Grid` rows above it, satisfying FR-006's "laid out
consistently with the other labelled rows". **That justification was wrong.**
SwiftUI sizes `Form` label columns per `Section` — this is stated in an existing
comment on the Grid itself, which is precisely why the Grid exists — and the
version row is its own `Section`, so its label column is sized to "Version" alone
and does not line up with the Grid's. The reversal still stands on the wrapping
and VoiceOver grounds, but not on alignment. FR-006's consistency requirement is
met in the weaker sense that the row uses the platform's standard labelled-row
control rather than a bespoke layout. Whether the visual result is acceptable is
a question for the pending manual acceptance run (quickstart steps 5 and 7); no
reviewer has yet seen it rendered.

## D4. Build-time stamping mechanism

**Decision**: In `scripts/build-app.sh`, immediately after `Info.plist` is copied
into the bundle and before `codesign` runs, set both keys on the **copy inside the
bundle** using `/usr/libexec/PlistBuddy`:

- `CFBundleShortVersionString` ← first available of: `$OVERTYPE_VERSION`
  environment variable; the exact tag at `HEAD` via
  `git describe --tags --exact-match` with a leading `v` stripped; otherwise leave
  the checked-in value untouched.
- `CFBundleVersion` ← `git rev-list --count HEAD` when the repository is
  available; otherwise leave the checked-in value untouched.

**Rationale**:

- Editing the bundle copy, never `Sources/Overtype/Resources/Info.plist`, keeps
  the working tree clean after a build and keeps the checked-in values as an
  intentional fallback.
- The ordering is not cosmetic. `codesign` seals `Info.plist`; any edit after
  signing invalidates the signature and macOS refuses to launch the bundle. The
  existing script signs last, so the stamping slots in naturally, but the
  constraint is written into the contract so it is not "simplified" later.
- `PlistBuddy` ships with macOS, edits in place, and does not rewrite unrelated
  keys. No new tool is introduced.
- The environment-variable-first precedence lets CI state the version explicitly
  instead of depending on how `git describe` behaves in a checkout, while a
  developer can still reproduce a release build locally with
  `OVERTYPE_VERSION=1.2.1 ./scripts/build-app.sh`.
- Commit count for `CFBundleVersion` is monotonic, requires no manual bookkeeping,
  and satisfies Apple's expectation that the build identifier increases. It also
  makes two builds of the same released version distinguishable, which is what
  User Story 2 needs.

**Alternatives considered**:

- *Keep the build identifier hand-edited*: it would stay at `2` release after
  release, making it useless for telling builds apart and re-creating the drift
  the clarification removed. Rejected.
- *Use the GitHub Actions run number for `CFBundleVersion`*: monotonic in CI, but
  meaningless and unreproducible locally, and it would differ between a local and
  a CI build of the same commit. Rejected.
- *Use `agvtool` or `xcodebuild` version settings*: this project has no Xcode
  project, only a Swift package plus a shell packaging script. Rejected as
  inapplicable.
- *Generate `Info.plist` from a template with `sed`*: more moving parts than
  setting two keys, and it would silently drop any key a future edit adds to the
  source plist. Rejected.

## D5. Checked-in fallback values in `Info.plist`

**Decision**: Set `CFBundleShortVersionString` to `1.2.1` (the current released
version) and `CFBundleVersion` to `0`.

**Rationale**: These values are only ever seen by a build that was not stamped,
which in practice means a local development build. `1.2.1` means such a build
never claims a version that does not exist. `0` is a deliberate marker: a build
identifier of zero cannot collide with any stamped build, since commit counts
start at 1, so `1.2.1 (0)` is recognisable as an unstamped local build without
adding any special-casing to the display logic.

**Alternatives considered**:

- *Leave `1.1` / `2`*: the whole point of the change is that these are wrong.
  Rejected.
- *Set the fallback to the current commit count (`20`)*: it would go stale
  immediately and pretend to be a real stamped build. Rejected.
- *Add a visible "local build" marker to the UI*: the spec explicitly accepts not
  distinguishing local builds as an out-of-scope, low-impact edge case. Rejected
  as scope creep.

## D6. Release workflow change

**Decision**: In `.github/workflows/release.yml`, pass the tag version to the
build step as an environment variable:
`OVERTYPE_VERSION="${GITHUB_REF_NAME#v}" ./scripts/build-app.sh`.

**Rationale**: The workflow already computes `${GITHUB_REF_NAME#v}` three times
for the zip name, the release upload and the cask. Reusing the same expression for
the stamped version guarantees, by construction, that the version shown in the app
equals the version in the release asset name and in the Homebrew cask (SC-007).
`fetch-depth: 0` is already set, so `git rev-list --count HEAD` produces the true
commit count in CI rather than a shallow-clone count.

**Alternatives considered**:

- *Rely on `git describe` inside the script during CI*: it would work given the
  full fetch, but it makes the workflow's correctness depend on an implicit
  property of the checkout. Explicit is safer and self-documenting. Rejected as
  the primary path, but kept as the script's second-choice fallback.

## D7. Test boundary

**Decision**: Unit-test only the pure formatting function, with inputs supplied as
parameters. Do not unit-test `Bundle.main` reading, the SwiftUI row, or the shell
script. Cover those in the manual procedure in `quickstart.md` and record the
result in `docs/compatibility.md`.

**Rationale**: This is Constitution Principle VIII applied directly. A test that
mocked `Bundle` would assert our belief about the bundle rather than the bundle.
The formatting rules, by contrast, are exactly the kind of pure logic the
constitution requires to be covered, and they carry all the fallback behaviour
that FR-007 and SC-005 depend on.

**Test cases planned**: both values present; build absent; short version absent;
both absent; whitespace-only short version; whitespace-only build; surrounding
whitespace trimmed; a pre-release version string such as `1.3.0-beta.1` passed
through unchanged.

**Alternatives considered**:

- *A test asserting the exact string shown by `GeneralTab`*: would require a view
  snapshot harness the project does not have, for one row of text. Rejected.
- *A shell test for the stamping script*: would need a scratch git repository and
  a full release build; the quickstart's `defaults read` check gives the same
  evidence in one command. Rejected as disproportionate.
