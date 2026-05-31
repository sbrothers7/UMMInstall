#!/bin/bash
set -e

GAME_PATH="$HOME/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice"
APP="$GAME_PATH/ADanceOfFireAndIce.app"
MACOS_DIR="$APP/Contents/MacOS"
EXE="$MACOS_DIR/ADanceOfFireAndIce"
REAL="$MACOS_DIR/ADanceOfFireAndIce.real"

if [ ! -d "$APP" ]; then
    echo "ADOFAI not found at $APP" >&2
    exit 1
fi

# When spawned from a .app (no login shell), /opt/homebrew/bin isn't on PATH.
# Source shellenv from known install locations before deciding brew is missing.
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew &>/dev/null; then
    echo "Homebrew not found — installing (you may be prompted for your password)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

if ! command -v brew &>/dev/null; then
    echo "error:Homebrew install failed. Install manually from https://brew.sh and re-run." >&2
    exit 1
fi

GAME_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null)
GAME_MAJOR="${GAME_VERSION%%.*}"
echo "Detected ADOFAI version: ${GAME_VERSION:-unknown}"

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
    # v2.x: legacy Unity 2022 build — Console.exe + arm64 strip
    # ============================================================
    command -v mono &>/dev/null || brew install mono
    command -v expect &>/dev/null || brew install expect
    command -v wget &>/dev/null || brew install wget

    echo "Downloading UnityModManager..."
    wget -q -O "$HOME/Downloads/UnityModManager.zip" "https://adof.ai/umm"
    rm -rf "$HOME/Downloads/UnityModManagerInstaller"
    unzip -o -q "$HOME/Downloads/UnityModManager.zip" -d "$HOME/Downloads/UnityModManagerInstaller"

    CONSOLE_EXE=$(find "$HOME/Downloads/UnityModManagerInstaller" -name "Console.exe" -maxdepth 3 | head -1)
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

    if [ "$(uname -m)" = "arm64" ] && lipo -info "$EXE" 2>/dev/null | grep -q "arm64"; then
        echo "Apple Silicon detected — stripping arm64 slice from game binary..."
        lipo -remove arm64 "$EXE" -output "$EXE.tmp"
        mv "$EXE.tmp" "$EXE"
        chmod +x "$EXE"
    fi

    rm -rf "$HOME/Downloads/UnityModManager.zip" "$HOME/Downloads/UnityModManagerInstaller"
else
    # ============================================================
    # v3.x+: Unity 6 build (use kkorenn/unity-mod-manager)
    # ============================================================
    command -v git &>/dev/null || brew install git
    command -v dotnet &>/dev/null || brew install dotnet

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

    echo "Installing Unity Mod Manager via MacTuiInstaller..."
    "$INSTALLER_BIN" --install --yes --game "$APP"
fi

echo "Done! Launch the game via Steam and press Ctrl+F10 for the UMM menu."
