#!/bin/bash
set -e

# Installs Unity Mod Manager the classic way: UMM's own Console.exe (run under
# mono) patches UnityEngine.CoreModule.dll in the game's Managed folder.
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

if [ "$(uname -m)" != "x86_64" ]; then
    echo "error:UMM on Linux supports x86_64 only." >&2
    exit 1
fi

# UMM and MelonLoader (with UMMBridge) would both start UMM and crash the game.
if [ -d "$GAME_PATH/MelonLoader" ]; then
    echo "error:MelonLoader is installed. Uninstall it first, then install UMM." >&2
    exit 1
fi

for tool in curl unzip mono expect; do
    if ! command -v "$tool" &>/dev/null; then
        echo "error:$tool is required — install curl, unzip, mono and expect with your package manager (e.g. sudo apt install curl unzip mono-complete expect)." >&2
        exit 1
    fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading Unity Mod Manager..."
if ! curl -fLsS -o "$WORK/UnityModManager.zip" "https://adof.ai/umm"; then
    echo "error:Failed to download Unity Mod Manager from https://adof.ai/umm" >&2
    exit 1
fi
unzip -o -q "$WORK/UnityModManager.zip" -d "$WORK/umm"

CONSOLE_EXE=$(find "$WORK/umm" -maxdepth 3 -name "Console.exe" | head -1)
if [ -z "$CONSOLE_EXE" ]; then
    echo "error:Console.exe not found in the Unity Mod Manager download." >&2
    exit 1
fi
rm -f "$(dirname "$CONSOLE_EXE")/UnityModManagerConfigLocal.xml"

echo "Patching UnityEngine.CoreModule.dll via UMM Console.exe..."
expect <<EOF
set timeout 30
set env(TERM) dumb
spawn mono "$CONSOLE_EXE"
expect -re "change sel"
send "y\r"
after 500
expect {
    -re "Enter a number" {
        send "1\r"
        exp_continue
    }
    -re "Enter the full path" {
        send "$GAME_PATH/\r"
        exp_continue
    }
    -re "D\\. Delete" {
        expect -re "Key:"
        send "R\r"
        expect -re "I\\. Install"
        expect -re "Key:"
        send "I\r"
    }
    -re "I\\. Install" {
        expect -re "Key:"
        send "I\r"
    }
}
expect {
    -re "Do you want to change it" { send "\r"; exp_continue }
    -re "Key:" { send "\r" }
    timeout { send "\r" }
}
expect eof
EOF

if [ ! -f "$MANAGED/UnityModManager/UnityModManager.dll" ]; then
    echo "error:UMM's installer finished without installing UMM into $MANAGED." >&2
    exit 1
fi

mkdir -p "$GAME_PATH/Mods"

echo ""
echo "ok:Unity Mod Manager installed."
echo "Launch the game via Steam and press Ctrl+F10 for the UMM menu."
