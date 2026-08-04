# Contract: Build-time version stamping

**Feature**: `006-settings-version-display` | **Surface**: `scripts/build-app.sh`

Defines how an application bundle comes to declare its own version, so that what
the General tab shows always matches the build the user actually installed
(FR-002a, FR-002b, SC-003, SC-007).

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| `OVERTYPE_VERSION` | Environment variable | No |
| Exact tag at `HEAD` | `git describe --tags --exact-match HEAD`, leading `v` stripped | No |
| Commit count | `git rev-list --count HEAD` | No |
| Existing declared values | `Sources/Overtype/Resources/Info.plist` | Yes (always present) |

## Resolution rules

**Released version** (`CFBundleShortVersionString`), first match wins:

1. `OVERTYPE_VERSION`, if set and non-empty.
2. The exact tag at `HEAD`, if `HEAD` is tagged.
3. Otherwise: leave the value already in the copied plist unchanged.

Whichever of 1 or 2 supplies the value, a single leading `v` is removed from it.
Both sources are normalised identically, so `OVERTYPE_VERSION=v1.2.1` and the tag
`v1.2.1` stamp the same value.

**Build identifier** (`CFBundleVersion`):

1. `git rev-list --count HEAD`, if the repository is **not** shallow and the
   command succeeds.
2. If the repository is shallow: leave the value unchanged and warn. A shallow
   clone returns a truncated count with exit status 0, so stamping it would
   produce a plausible but wrong build identifier, which is worse than not
   stamping at all.
3. Otherwise (no git metadata at all): leave the value unchanged.

Neither rule may fail the build. A source tree with no git metadata and no
environment variable MUST still produce a working bundle, using the checked-in
fallback values.

Because the two keys resolve independently, an ordinary local build in a full
clone declares the fallback version paired with a real commit count, and is
therefore shaped like a release. That is accepted: distinguishing local builds
from releases is explicitly not a goal (see the spec's Edge Cases). The `0`
fallback for the build identifier is reached only when the count is unavailable,
which means a source tarball or a shallow clone.

## Outputs

The bundle at `Overtype.app/Contents/Info.plist` declares the resolved version and
build. Example for a release built from tag `v1.2.1` at commit count 20:

```text
CFBundleShortVersionString = 1.2.1
CFBundleVersion            = 20
```

## Invariants

1. **Signature ordering.** Stamping MUST happen after `Info.plist` is copied into
   the bundle and BEFORE `codesign` runs. `codesign` seals `Info.plist`; editing
   it afterwards invalidates the signature and macOS refuses to launch the app.
   This ordering is a platform constraint, not a stylistic choice, and must not be
   rearranged without re-verifying with `codesign --verify`.
2. **No writes to the repository.** Only the copy inside `Overtype.app` is
   modified. `Sources/Overtype/Resources/Info.plist` MUST be byte-identical before
   and after a build, so `git status` stays clean.
3. **Key preservation.** Every other key in `Info.plist` (`CFBundleIdentifier`,
   `LSUIElement`, `LSMinimumSystemVersion`, and the rest) MUST survive stamping
   unchanged.
4. **Idempotence.** Running the build twice on the same commit produces the same
   two values.
5. **Reproducibility.** `OVERTYPE_VERSION=1.2.1 ./scripts/build-app.sh` locally
   produces the same declared version as the CI release build of tag `v1.2.1`.

## Release pipeline obligation

`.github/workflows/release.yml` MUST pass the tag version to the build step:

```yaml
OVERTYPE_VERSION="${GITHUB_REF_NAME#v}" ./scripts/build-app.sh
```

This is the same expression the workflow already uses for the zip filename, the
GitHub release upload and the Homebrew cask, so the version shown inside the
application and the version in the published artifact names cannot diverge.

The workflow's existing `fetch-depth: 0` checkout is required for the commit count
to be available. Lowering it does not corrupt the build identifier, because rule 2
above refuses to stamp from a shallow clone, but it does downgrade the released
build identifier to the `0` fallback.

## Checked-in fallback values

`Sources/Overtype/Resources/Info.plist` holds the values used when nothing is
stamped:

| Key | Value | Meaning |
|-----|-------|---------|
| `CFBundleShortVersionString` | `1.2.1` | Current released version, so an unstamped build never claims a version that does not exist. |
| `CFBundleVersion` | `0` | Sentinel for "commit count unavailable" (source tarball or shallow clone). Commit counts start at 1, so `0` cannot collide with a real build. Note this is narrower than "not stamped": an ordinary local build in a full clone does get a real count. |
