#!/bin/bash
set -e

# $1: the game folder (contains "A Dance of Fire and Ice_Data").
GAME_PATH="${1:-}"
DATA="$GAME_PATH/A Dance of Fire and Ice_Data"

if [ -z "$GAME_PATH" ] || [ ! -d "$DATA" ]; then
    echo "error:ADOFAI not found at ${GAME_PATH:-<no game folder given>}" >&2
    exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "error:MelonLoader on Linux supports x86_64 only." >&2
    exit 1
fi

command -v curl &>/dev/null || { echo "error:curl is required — install it with your package manager." >&2; exit 1; }
command -v unzip &>/dev/null || { echo "error:unzip is required — install it with your package manager." >&2; exit 1; }

MELON_VERSION="0.7.3"
ARCHIVE="MelonLoader.Linux.x64.zip"
URL="https://github.com/kkorenn/MelonLoader/releases/download/v${MELON_VERSION}/${ARCHIVE}"

echo "Detected ADOFAI install at $GAME_PATH"

# Clean up UMM remnants: restore patched DLLs from backups, remove
# UnityModManager folders. MelonLoader can't coexist with UMM's assembly
# patching.
MANAGED="$DATA/Managed"

if [ -d "$MANAGED" ]; then
    for DLL in UnityEngine.CoreModule.dll UnityEngine.dll; do
        if [ -f "$MANAGED/$DLL.bak" ]; then
            echo "Restoring $DLL from .bak"
            rm -f "$MANAGED/$DLL"
            mv "$MANAGED/$DLL.bak" "$MANAGED/$DLL"
        elif [ -f "$MANAGED/$DLL.original" ]; then
            echo "Restoring $DLL from .original"
            rm -f "$MANAGED/$DLL"
            mv "$MANAGED/$DLL.original" "$MANAGED/$DLL"
        fi
    done
    rm -rf "$MANAGED/UnityModManager"
fi

# Remove prior MelonLoader artifacts so the extract is clean.
echo "Removing any prior MelonLoader artifacts..."
rm -rf "$GAME_PATH/MelonLoader" \
       "$GAME_PATH/MelonLoader.Bootstrap.so" \
       "$GAME_PATH/setup_helper.sh" \
       "$GAME_PATH/NOTICE.txt"

echo "Downloading $ARCHIVE..."
TMP_ZIP="$(mktemp)"
if ! curl -fLsS -o "$TMP_ZIP" "$URL"; then
    rm -f "$TMP_ZIP"
    echo "error:Failed to download $URL" >&2
    exit 1
fi

echo "Extracting into game folder..."
unzip -o -q "$TMP_ZIP" -d "$GAME_PATH"
rm -f "$TMP_ZIP"

# Write version marker so future installs/uninstalls know what we put down.
mkdir -p "$GAME_PATH/MelonLoader"
echo "$MELON_VERSION" > "$GAME_PATH/MelonLoader/MelonLoader.version"

# Write the Steam launch helper. The bootstrap is named by file name only in
# LD_PRELOAD and found via LD_LIBRARY_PATH.
cat > "$GAME_PATH/setup_helper.sh" <<'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_PRELOAD="MelonLoader.Bootstrap.so${LD_PRELOAD:+:$LD_PRELOAD}"
exec "$@"
EOF
chmod +x "$GAME_PATH/setup_helper.sh"

# Pre-create both mod folders. The UMMBridge plugin reads UMMMods/; native
# MelonLoader mods go in Mods/.
mkdir -p "$GAME_PATH/UMMMods"
mkdir -p "$GAME_PATH/Mods"

# UMMBridge (modlist.org) replaces UMMCompat; two such plugins start UMM twice
# and crash the game, so UMMCompat's files go first.
if [ -f "$GAME_PATH/Plugins/UMMCompat.dll" ]; then
    echo "Removing UMMCompat (replaced by UMMBridge)..."
    rm -f "$GAME_PATH/Plugins/UMMCompat.dll"
    for f in UnityModManager.dll UnityModManager.xml dnlib.dll Config.xml; do
        rm -f "$GAME_PATH/UserLibs/$f"
    done
fi

# Install UMMBridge — the MelonLoader plugin that loads UMM mods from
# UMMMods/. Its zip names the game's data folder __gamename___Data: use the
# game's own (the Proton build's differs from the native one).
echo "Downloading UMMBridge..."
BRIDGE_ZIP="$(mktemp)"
if curl -fLsS -o "$BRIDGE_ZIP" "https://github.com/modlist-org/UMMBridge/releases/latest/download/UMMBridge.zip"; then
    DATA_DIR="$(cd "$GAME_PATH" && ls -d -- *_Data 2>/dev/null | head -1)"
    STAGE="$(mktemp -d)"
    unzip -o -q "$BRIDGE_ZIP" -d "$STAGE"
    if [ -d "$STAGE/__gamename___Data" ]; then
        mkdir -p "$STAGE/${DATA_DIR:-ADanceOfFireAndIce_Data}"
        cp -R "$STAGE/__gamename___Data/." "$STAGE/${DATA_DIR:-ADanceOfFireAndIce_Data}/"
        rm -rf "$STAGE/__gamename___Data"
    fi
    cp -R "$STAGE/." "$GAME_PATH/"
    rm -rf "$STAGE" "$BRIDGE_ZIP"
    echo "ok:UMMBridge installed."
else
    rm -f "$BRIDGE_ZIP"
    echo "error:Failed to download UMMBridge — UMM mods in UMMMods/ won't load until it's installed."
fi

echo ""
echo "ok:MelonLoader $MELON_VERSION installed."
echo ""
