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
