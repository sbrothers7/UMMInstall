#!/bin/bash
set -e

# Undoes adofai-umm.sh: puts back the DLLs UMM's installer backed up and
# removes its UnityModManager folder. Mods/ is left alone.
# $1: the game folder (contains "A Dance of Fire and Ice_Data").
GAME_PATH="${1:-}"
DATA="$GAME_PATH/A Dance of Fire and Ice_Data"
MANAGED="$DATA/Managed"

if [ -z "$GAME_PATH" ] || [ ! -d "$DATA" ]; then
    echo "error:ADOFAI not found at ${GAME_PATH:-<no game folder given>}" >&2
    exit 1
fi

echo "Removing Unity Mod Manager..."
for DLL in UnityEngine.CoreModule.dll UnityEngine.dll; do
    if [ -f "$MANAGED/$DLL.bak" ]; then
        echo "  restoring $DLL from .bak"
        rm -f "$MANAGED/$DLL"
        mv "$MANAGED/$DLL.bak" "$MANAGED/$DLL"
    elif [ -f "$MANAGED/$DLL.original" ]; then
        echo "  restoring $DLL from .original"
        rm -f "$MANAGED/$DLL"
        mv "$MANAGED/$DLL.original" "$MANAGED/$DLL"
    fi
done
rm -rf "$MANAGED/UnityModManager"

echo ""
echo "ok:Unity Mod Manager uninstalled."
