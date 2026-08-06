# Vendored KeyboardShortcuts

Upstream: <https://github.com/sindresorhus/KeyboardShortcuts>
Version: `1.15.0`
Revision: `ac302e21da5883f4bd0490cbd0cb710b08740500`
License: MIT (see `license`, retained unmodified)

## Why this is vendored rather than fetched

`swift build` generates this resource accessor for any SwiftPM target that has
resources, and KeyboardShortcuts has resources because it declares
`defaultLocalization: "en"` with `Sources/KeyboardShortcuts/Localization/*.lproj`:

```swift
let mainPath  = Bundle.main.bundleURL.appendingPathComponent("KeyboardShortcuts_KeyboardShortcuts.bundle").path
let buildPath = "<absolute .build path of the machine that compiled it>"
guard let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath) else { Swift.fatalError(...) }
```

Neither candidate can be satisfied by a shippable `.app`:

- `Bundle.main.bundleURL` is the `.app` **root**, and macOS forbids any entry
  beside `Contents` in a bundle root. Placing the resource bundle (or a symlink
  to it) there makes `codesign` fail with "unsealed contents present in the
  bundle root" and `spctl -a` reject the app. Verified empirically, not assumed.
- `buildPath` is the absolute path of the machine that compiled the binary. In a
  release it points into the GitHub Actions runner's home directory and never
  exists on a user's machine.

The result was a hard `fatalError` (`EXC_BREAKPOINT`) the first time
`KeyboardShortcuts.Recorder` rendered, i.e. every time a user opened
Settings > Actions and clicked Add Action or Edit. Upstream does not hit this
because Xcode generates a different accessor that consults
`Bundle.main.resourceURL` (`Contents/Resources`), which is the legal location.

Since the defect is in generated dependency code, it cannot be fixed from the
app target or from the packaging script. Hence the local patch below.

## Local changes to upstream

Keep this list exact. Anyone re-syncing with a newer upstream must re-apply it.

1. `Sources/KeyboardShortcuts/Utilities.swift` — `String.localized` no longer
   reads `Bundle.module`. It uses `Bundle.keyboardShortcutsResources`, a lookup
   that tries the legal `.app` location first and returns `nil` instead of
   trapping. A missing resource bundle now degrades to the untranslated key
   rather than killing the process.
2. `Package.swift` — upstream's `testTarget` is removed, because `Tests/` is not
   vendored.

Nothing else is modified. The localization files are vendored unchanged, so all
14 languages still work.
