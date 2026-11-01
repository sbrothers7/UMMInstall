#!/bin/bash
set -e

# $1: the game folder (contains "A Dance of Fire and Ice_Data").
GAME_PATH="${1:-}"

if [ -z "$GAME_PATH" ] || [ ! -d "$GAME_PATH/A Dance of Fire and Ice_Data" ]; then
    echo "error:ADOFAI not found at ${GAME_PATH:-<no game folder given>}" >&2
    exit 1
fi

echo "Removing MelonLoader artifacts..."

TARGETS=(
    "MelonLoader"
    "MelonLoader.Bootstrap.so"
    "setup_helper.sh"
    "NOTICE.txt"
    "version.dll"
    "winhttp.dll"
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
