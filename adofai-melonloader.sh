#!/bin/bash
set -e

GAME_PATH="$HOME/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice"
APP="$GAME_PATH/ADanceOfFireAndIce.app"
MACOS_DIR="$APP/Contents/MacOS"
EXE="$MACOS_DIR/ADanceOfFireAndIce"
REAL="$MACOS_DIR/ADanceOfFireAndIce.real"

if [ ! -d "$APP" ]; then
    echo "error:ADOFAI not found at $APP" >&2
    exit 1
fi

# Detect real hardware arch (works even if this script is under Rosetta).
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
    ARCH="arm64"
    ARCH_FLAG="arm64"
else
    ARCH="x64"
    ARCH_FLAG="x86_64"
fi

MELON_VERSION="0.7.3"
ARCHIVE="MelonLoader.macOS.${ARCH}.zip"
URL="https://github.com/kkorenn/MelonLoader/releases/download/v${MELON_VERSION}/${ARCHIVE}"

echo "Detected ADOFAI install at $GAME_PATH"
echo "Architecture: $ARCH"

# On Apple Silicon, MelonLoader's arm64 bootstrap can only inject into the
# arm64 slice of the game binary. v2.x UMM installs strip that slice for
# Rosetta; if so, the user must verify game files via Steam first.
if [ "$ARCH" = "arm64" ] && [ -x "$EXE" ]; then
    if ! lipo -info "$EXE" 2>/dev/null | grep -q "arm64"; then
        echo "error:Game binary is missing its arm64 slice (likely stripped by a previous v2 UMM install)." >&2
        echo "error:Verify game files via Steam → Properties → Installed Files, then re-run this installer." >&2
        exit 1
    fi
fi

# Reconcile launcher/real state from any previous UMM launcher install.
if [ -f "$REAL" ]; then
    EXE_SIZE=$(stat -f%z "$EXE" 2>/dev/null || echo 0)
    if [ "$EXE_SIZE" -lt 30000 ]; then
        echo "Restoring real binary from previous UMM launcher install..."
        rm -f "$EXE"
        mv "$REAL" "$EXE"
    else
        rm -f "$REAL"
    fi
fi

# Clean up UMM remnants: restore patched DLLs from backups, remove
# UnityModManager folders. MelonLoader can't coexist with UMM's assembly
# patching.
MANAGED="$APP/Contents/Resources/Data/Managed"
ASSEMBLY="$APP/Contents/Resources/Data/Assembly"

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

if [ -d "$ASSEMBLY" ]; then
    rm -rf "$ASSEMBLY/UnityModManager"
fi

# Remove prior MelonLoader artifacts so the extract is clean.
echo "Removing any prior MelonLoader artifacts..."
rm -rf "$GAME_PATH/MelonLoader" \
       "$GAME_PATH/MelonLoader.Bootstrap.dylib" \
       "$GAME_PATH/MelonLoader.Bootstrap.dylib.dSYM" \
       "$GAME_PATH/setup_helper.sh" \
       "$GAME_PATH/melonloader-launch.sh" \
       "$GAME_PATH/libMelonLoader.dylib" \
       "$GAME_PATH/NOTICE.txt"

echo "Downloading $ARCHIVE..."
TMP_ZIP="/tmp/adofai-melonloader.zip"
rm -f "$TMP_ZIP"
if ! curl -fLsS -o "$TMP_ZIP" "$URL"; then
    echo "error:Failed to download $URL" >&2
    exit 1
fi

echo "Extracting into game folder..."
ditto -x -k "$TMP_ZIP" "$GAME_PATH"
rm -f "$TMP_ZIP"

# Write version marker so future installs/uninstalls know what we put down.
mkdir -p "$GAME_PATH/MelonLoader"
echo "$MELON_VERSION" > "$GAME_PATH/MelonLoader/MelonLoader.version"

# Write the Steam launch helper.
cat > "$GAME_PATH/setup_helper.sh" <<EOF
#!/bin/bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

# Steam passes the .app bundle as %command%. DYLD_INSERT_LIBRARIES is dropped
# when LaunchServices opens a .app, so exec the inner Mach-O binary directly.
if [ -d "\${1:-}" ] && [ "\${1%.app}" != "\$1" ]; then
  APP="\$1"; shift
  BIN_NAME="\$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "\$APP/Contents/Info.plist" 2>/dev/null)"
  set -- "\$APP/Contents/MacOS/\$BIN_NAME" "\$@"
fi

# The installed $ARCH bootstrap can only inject into the $ARCH_FLAG game slice.
# Re-run this helper under that architecture before setting DYLD_INSERT_LIBRARIES,
# otherwise dyld may try to inject the bootstrap into the wrong-architecture shell.
if [ "\$MELON_ARCH_SET" != "1" ] && [ "\$(/usr/sbin/sysctl -in hw.optional.arm64 2>/dev/null)" = "1" ]; then
  export MELON_ARCH_SET=1
  exec arch -$ARCH_FLAG /bin/bash "\$0" "\$@"
fi

BOOTSTRAP="\$DIR/MelonLoader.Bootstrap.dylib"

export DYLD_LIBRARY_PATH="\$DIR\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}"
if [ -n "\$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  export DYLD_INSERT_LIBRARIES="\$BOOTSTRAP:\$STEAM_DYLD_INSERT_LIBRARIES"
else
  export DYLD_INSERT_LIBRARIES="\$BOOTSTRAP\${DYLD_INSERT_LIBRARIES:+:\$DYLD_INSERT_LIBRARIES}"
fi

exec "\$@"
EOF
chmod +x "$GAME_PATH/setup_helper.sh"

# Clear quarantine so dyld doesn't refuse to inject the bootstrap.
xattr -d com.apple.quarantine "$GAME_PATH/MelonLoader.Bootstrap.dylib" 2>/dev/null || true
xattr -d com.apple.quarantine "$GAME_PATH/setup_helper.sh" 2>/dev/null || true
xattr -dr com.apple.quarantine "$GAME_PATH/MelonLoader" 2>/dev/null || true

# Pre-create both mod folders. The UMMCompat plugin reads UMMMods/; native
# MelonLoader mods go in Mods/.
mkdir -p "$GAME_PATH/UMMMods"
mkdir -p "$GAME_PATH/Mods"

# Install UMMCompat (square3ang) — the MelonLoader plugin that loads UMM mods
# from UMMMods/. Its zip lays down Plugins/ and UserLibs/ at the game root.
echo "Downloading UMMCompat (square3ang)..."
UMMCOMPAT_ZIP="/tmp/adofai-ummcompat.zip"
rm -f "$UMMCOMPAT_ZIP"
if curl -fLsS -o "$UMMCOMPAT_ZIP" "https://github.com/modlist-org/UMMCompat/releases/latest/download/UMMCompat.zip"; then
    ditto -x -k "$UMMCOMPAT_ZIP" "$GAME_PATH"
    rm -f "$UMMCOMPAT_ZIP"
    xattr -dr com.apple.quarantine "$GAME_PATH/Plugins" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$GAME_PATH/UserLibs" 2>/dev/null || true
    echo "ok:UMMCompat installed."
else
    echo "error:Failed to download UMMCompat — UMM mods in UMMMods/ won't load until it's installed."
fi

echo ""
echo "ok:MelonLoader $MELON_VERSION installed."
echo ""
echo "info:IMPORTANT — set the game's Steam Launch Options to:"
echo "info:  \"$GAME_PATH/setup_helper.sh\" %command%"
echo "info:(Steam → Library → A Dance of Fire and Ice → Properties → Launch Options)"
