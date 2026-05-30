#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="macOS ADOFAI Mod Installer"
BUNDLE_ID="com.sbrothers.macos-adofai-mod-installer"
ICON_SRC="../icon.png"

# Use /tmp for build artifacts — some source-tree locations (iCloud-synced
# directories) confuse SwiftPM's SQLite build database with disk I/O errors.
BUILD_PATH="/tmp/adofai-mm-build"

# Universal builds (--arch arm64 --arch x86_64) require full Xcode (xcbuild).
# With just CLI Tools we build single-arch native. Pass UNIVERSAL=1 to attempt
# a universal build (Xcode required).
if [ "$UNIVERSAL" = "1" ]; then
    echo "Building (universal arm64 + x86_64)..."
    swift build -c release --arch arm64 --arch x86_64 --build-path "$BUILD_PATH"
else
    echo "Building (host arch)..."
    swift build -c release --build-path "$BUILD_PATH"
fi

if [ -f "$BUILD_PATH/apple/Products/Release/ADOFAIModManager" ]; then
    BIN_PATH="$BUILD_PATH/apple/Products/Release/ADOFAIModManager"
else
    BIN_PATH="$BUILD_PATH/release/ADOFAIModManager"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "Build failed: binary not found"
    exit 1
fi

APP_DIR="$APP_NAME.app"
echo "Wrapping into $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/ADOFAIModManager"

# Build AppIcon.icns from icon.png
if [ -f "$ICON_SRC" ]; then
    echo "Generating AppIcon.icns from $ICON_SRC..."
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
                "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
        size="${spec%%:*}"
        name="${spec##*:}"
        sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/$name.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
else
    echo "Warning: $ICON_SRC not found — skipping icon"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ADOFAIModManager</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"

if [ "$1" = "--zip" ]; then
    rm -f "$APP_NAME.zip"
    ditto -c -k --keepParent "$APP_DIR" "$APP_NAME.zip"
    echo "Packaged: $APP_NAME.zip"
fi
