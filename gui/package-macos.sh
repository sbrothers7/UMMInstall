#!/bin/bash
# Builds and packages the macOS app into ADOFAIModInstaller-macos.zip (the asset
# name the updater expects). Windows/Linux artifacts are produced by CI
# (.github/workflows/release-gui.yml).
set -e
cd "$(dirname "$0")"

echo "Building macOS release…"
flutter build macos --release

APP="build/macos/Build/Products/Release/adofai_mod_installer.app"
if [ ! -d "$APP" ]; then
    echo "Build failed: $APP not found" >&2
    exit 1
fi

rm -f ADOFAIModInstaller-macos.zip
ditto -c -k --keepParent "$APP" ADOFAIModInstaller-macos.zip
echo "Packaged: gui/ADOFAIModInstaller-macos.zip"
