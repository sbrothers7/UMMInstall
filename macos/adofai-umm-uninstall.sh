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

# Source brew shellenv so subsequent tool checks see Homebrew binaries. Use
# sysctl rather than `uname -m` so we get the real hardware arch even when
# this script happens to be running under Rosetta.
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
    BREW_BIN="/opt/homebrew/bin/brew"
else
    BREW_BIN="/usr/local/bin/brew"
fi
if [ -x "$BREW_BIN" ]; then
    eval "$($BREW_BIN shellenv)"
fi

GAME_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null)
GAME_MAJOR="${GAME_VERSION%%.*}"
echo "Detected ADOFAI version: ${GAME_VERSION:-unknown}"

# Reconcile launcher/real state from any previous launcher install.
if [ -f "$REAL" ]; then
    EXE_SIZE=$(stat -f%z "$EXE" 2>/dev/null || echo 0)
    if [ "$EXE_SIZE" -lt 30000 ]; then
        echo "Restoring real binary from previous launcher install..."
        rm -f "$EXE"
        mv "$REAL" "$EXE"
    else
        echo "Removing stale .real from previous install..."
        rm -f "$REAL"
    fi
fi

if [ "$GAME_MAJOR" = "2" ]; then
    # ============================================================
    # v2.x: legacy Unity 2022 build — Console.exe Restore
    # ============================================================
    command -v mono &>/dev/null   || { echo "error:mono is required to uninstall on v2.x" >&2; exit 1; }
    command -v expect &>/dev/null || { echo "error:expect is required to uninstall on v2.x" >&2; exit 1; }
    command -v wget &>/dev/null   || { echo "error:wget is required to uninstall on v2.x" >&2; exit 1; }

    if [ ! -d "$HOME/Downloads/UnityModManagerInstaller" ]; then
        echo "Downloading UnityModManager for restore tooling..."
        wget -q -O "$HOME/Downloads/UnityModManager.zip" "https://adof.ai/umm"
        unzip -o -q "$HOME/Downloads/UnityModManager.zip" -d "$HOME/Downloads/UnityModManagerInstaller"
    fi

    CONSOLE_EXE=$(find "$HOME/Downloads/UnityModManagerInstaller" -name "Console.exe" -maxdepth 3 | head -1)
    rm -f "$(dirname "$CONSOLE_EXE")/UnityModManagerConfigLocal.xml"

    echo "Restoring UnityEngine.CoreModule.dll via UMM Console.exe..."
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
    -re "R\\. Restore" {
        expect -re "Key:"
        send "R\r"
    }
    timeout {}
}
expect {
    -re "Key:" { send "\r" }
    timeout {}
}
expect eof
EOF

    rm -rf "$HOME/Downloads/UnityModManager.zip" "$HOME/Downloads/UnityModManagerInstaller"

    echo "Note: the arm64 slice of the game binary was previously stripped. Verify integrity via Steam (Properties > Local Files) to restore it if desired."
else
    # ============================================================
    # v3.x+: kkorenn/unity-mod-manager MacTuiInstaller --remove
    # ============================================================
    command -v git &>/dev/null    || { echo "error:git is required to uninstall on v3.x" >&2; exit 1; }
    command -v dotnet &>/dev/null || { echo "error:dotnet is required to uninstall on v3.x" >&2; exit 1; }

    CACHE_DIR="$HOME/.cache/adofai-umm-installer"
    SRC_DIR="$CACHE_DIR/src"
    INSTALLER_BIN="$CACHE_DIR/adofai-umm"

    mkdir -p "$CACHE_DIR"
    if [ ! -x "$INSTALLER_BIN" ]; then
        echo "Fetching kkorenn/unity-mod-manager..."
        rm -rf "$SRC_DIR"
        git clone --depth=1 https://github.com/kkorenn/unity-mod-manager.git "$SRC_DIR"

        echo "Building MacTuiInstaller (one-time, ~30-60s)..."
        dotnet publish "$SRC_DIR/MacTuiInstaller/MacTuiInstaller.csproj" \
            -c Release -r osx-arm64 --self-contained true \
            -o "$CACHE_DIR/build" --nologo --verbosity quiet
        cp "$CACHE_DIR/build/adofai-umm" "$INSTALLER_BIN"
        chmod +x "$INSTALLER_BIN"
        rm -rf "$SRC_DIR" "$CACHE_DIR/build"
    fi

    echo "Removing Unity Mod Manager via MacTuiInstaller..."
    "$INSTALLER_BIN" --remove --yes --game "$APP"
fi

# MacTuiInstaller --remove leaves the UnityModManager directory (and the DLL) remove it detection works after uninstall
rm -rf "$APP/Contents/Resources/Data/Managed/UnityModManager"

echo "Done! Unity Mod Manager has been uninstalled."
