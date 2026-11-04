#!/bin/bash
set -e

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

if [ -z "$GAME_PATH" ] || [ -z "$DATA" ]; then
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

# UMMBridge's copy of UMM. Under MelonLoader nothing else puts UMM there (the
# installer clears a UMM install first), and left behind it reads as one.
rm -rf "$DATA/Managed/UnityModManager"

echo ""
echo "ok:MelonLoader uninstalled."
echo ""
