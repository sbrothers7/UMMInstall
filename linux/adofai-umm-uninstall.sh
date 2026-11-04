#!/bin/bash
set -e

# Undoes adofai-umm.sh: puts back the DLLs UMM's installer backed up and
# removes its UnityModManager folder. Mods/ is left alone.
# $1: the game folder (contains the game's *_Data folder).
GAME_PATH="${1:-}"

# The Unity data folder: ADanceOfFireAndIce_Data on the native build, "A Dance
# of Fire and Ice_Data" on the Windows (Proton) one. The one holding
# globalgamemanagers wins, as a stray folder of the other name can sit beside it.
find_data() {
    local n
    for n in ADanceOfFireAndIce_Data "A Dance of Fire and Ice_Data"; do
        if [ -f "$1/$n/globalgamemanagers" ]; then echo "$1/$n"; return; fi
    done
    for n in ADanceOfFireAndIce_Data "A Dance of Fire and Ice_Data"; do
        if [ -d "$1/$n" ]; then echo "$1/$n"; return; fi
    done
}

DATA="$(find_data "$GAME_PATH")"
MANAGED="$DATA/Managed"

if [ -z "$GAME_PATH" ] || [ -z "$DATA" ]; then
    echo "error:ADOFAI not found at ${GAME_PATH:-<no game folder given>}" >&2
    exit 1
fi

echo "Removing Unity Mod Manager..."
for DLL in UnityEngine.CoreModule.dll UnityEngine.dll; do
    # UMM's installer backs up as .original_; older ones used .bak/.original.
    for EXT in .original_ .bak .original; do
        if [ -f "$MANAGED/$DLL$EXT" ]; then
            echo "  restoring $DLL from $EXT"
            rm -f "$MANAGED/$DLL"
            mv "$MANAGED/$DLL$EXT" "$MANAGED/$DLL"
            break
        fi
    done
done
rm -rf "$MANAGED/UnityModManager"

echo ""
echo "ok:Unity Mod Manager uninstalled."
