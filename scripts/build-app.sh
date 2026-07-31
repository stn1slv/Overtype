#!/bin/bash
set -e

APP_NAME="Overtype"
APP_BUNDLE="$APP_NAME.app"
BIN_DIR=".build/release"
RESOURCES_DIR="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"

echo "Building executable..."
swift build -c release

echo "Creating App Bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Copying executable..."
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

echo "Copying Info.plist..."
if [ -f "Sources/Overtype/Resources/Info.plist" ]; then
    cp "Sources/Overtype/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
    echo "Warning: Info.plist not found in Sources/Overtype/Resources/"
fi

# Copy any bundle resources if they exist
if [ -d "$RESOURCES_DIR" ]; then
    echo "Copying resources..."
    cp -R "$RESOURCES_DIR/"* "$APP_BUNDLE/Contents/Resources/"
fi

echo "Codesigning (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Done! App bundle created at $APP_BUNDLE"
