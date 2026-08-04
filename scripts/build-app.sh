#!/bin/bash
set -e

APP_NAME="Overtype"
APP_BUNDLE="$APP_NAME.app"
BIN_DIR=".build/release"

echo "Building executable..."
swift build -c release

echo "Creating App Bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Copying executable..."
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

echo "Copying Info.plist..."
if [ -f "Sources/Overtype/Resources/Info.plist" ]; then
    cp Sources/Overtype/Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
    if [ -f "Sources/Overtype/Resources/AppIcon.icns" ]; then
        cp Sources/Overtype/Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
    fi
else
    echo "Warning: Info.plist not found in Sources/Overtype/Resources/"
fi

# Stamp the version the app reports about itself, so Settings > General can never
# show a version that disagrees with the release the user installed.
#
# ORDERING CONSTRAINT: this must run after the plist is copied and BEFORE
# codesign. codesign seals Info.plist; editing it afterwards invalidates the
# signature and macOS refuses to launch the bundle. Do not move this below the
# signing step. Verify with `codesign --verify --deep --strict Overtype.app`.
#
# Only the copy inside the bundle is touched. Sources/Overtype/Resources/Info.plist
# stays untouched, so its values remain the fallback for an unstamped build.
if [ -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    # Version: explicit override, else the exact tag at HEAD, else leave as-is.
    STAMP_VERSION="${OVERTYPE_VERSION:-}"
    if [ -z "$STAMP_VERSION" ]; then
        # `|| true` because the repo may be untagged here and `set -e` is on.
        GIT_TAG="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
        STAMP_VERSION="${GIT_TAG#v}"
    fi
    # Build: commit count, else leave as-is (no git metadata available).
    STAMP_BUILD="$(git rev-list --count HEAD 2>/dev/null || true)"

    if [ -n "$STAMP_VERSION" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $STAMP_VERSION" \
            "$APP_BUNDLE/Contents/Info.plist"
        echo "Stamped version $STAMP_VERSION"
    else
        echo "No tag or OVERTYPE_VERSION; keeping the version declared in Info.plist"
    fi

    if [ -n "$STAMP_BUILD" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $STAMP_BUILD" \
            "$APP_BUNDLE/Contents/Info.plist"
        echo "Stamped build $STAMP_BUILD"
    else
        echo "No git metadata; keeping the build declared in Info.plist"
    fi
fi

# Copy every SwiftPM resource bundle (our own and dependencies') next to the
# executable. KeyboardShortcuts crashes on first use of its Recorder view
# because Bundle.module hard-fails when KeyboardShortcuts_KeyboardShortcuts.bundle
# is missing, so all *.bundle directories must ship inside the app.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    dest="$APP_BUNDLE/Contents/Resources/$(basename "$bundle")"
    echo "Copying resource bundle $(basename "$bundle")..."
    rm -rf "$dest"
    cp -R "$bundle" "$dest"
done
shopt -u nullglob

echo "Codesigning (ad-hoc)..."
codesign --force --deep --sign - -i com.github.stn1slv.Overtype "$APP_BUNDLE"

echo "Done! App bundle created at $APP_BUNDLE"
