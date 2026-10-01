#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="BoardLock.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
BUILD_DIR="${INPUTSOURCELOCK_BUILD_DIR:-$PROJECT_DIR/.build}"

echo "==> Building BoardLock (Release configuration)..."
cd "$PROJECT_DIR"
swift build -c release --scratch-path "$BUILD_DIR" --product BoardLock

BIN_PATH="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)"
EXECUTABLE="$BIN_PATH/BoardLock"

if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: Executable not found at $EXECUTABLE"
    exit 1
fi

if [ "$(lipo -archs "$EXECUTABLE")" != "arm64" ]; then
    echo "Error: This package is intended for Apple Silicon (arm64) Macs."
    exit 1
fi

echo "==> Creating macOS App Bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/BoardLock"
chmod +x "$APP_BUNDLE/Contents/MacOS/BoardLock"

echo "==> Writing Info.plist (LSUIElement = true)..."
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BoardLock</string>
    <key>CFBundleIdentifier</key>
    <string>com.inputsourcelock.app</string>
    <key>CFBundleName</key>
    <string>BoardLock</string>
    <key>CFBundleDisplayName</key>
    <string>BoardLock</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.3</string>
    <key>CFBundleVersion</key>
    <string>4</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

plutil -lint "$APP_BUNDLE/Contents/Info.plist"

echo "==> Ad-hoc code signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign -vvv --deep --strict "$APP_BUNDLE"

echo "==> Build and packaging successful: $APP_BUNDLE"
