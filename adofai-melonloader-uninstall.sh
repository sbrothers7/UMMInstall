#!/bin/bash
set -e

GAME_PATH="$HOME/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice"
APP="$GAME_PATH/ADanceOfFireAndIce.app"

if [ ! -d "$APP" ]; then
    echo "error:ADOFAI not found at $APP" >&2
    exit 1
fi

echo "Removing MelonLoader artifacts..."

TARGETS=(
    "MelonLoader"
    "MelonLoader.Bootstrap.dylib"
    "MelonLoader.Bootstrap.dylib.dSYM"
    "libMelonLoader.so"
    "libMelonLoader.dylib"
    "setup_helper.sh"
    "melonloader-launch.sh"
    "winhttp.dll"
    "version.dll"
    "NOTICE.txt"
)

for T in "${TARGETS[@]}"; do
    P="$GAME_PATH/$T"
    if [ -e "$P" ] || [ -L "$P" ]; then
        echo "  rm $T"
        rm -rf "$P"
    fi
done

echo ""
echo "ok:MelonLoader uninstalled."
echo ""
echo "info:Remove the Steam Launch Options entry (Properties → Launch Options) if you set one."
