#!/bin/bash
#
# install.sh — install the amm CLI (and the ammtui menu alias).
#
#   curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/cli/install.sh | bash
#
# Downloads the latest release binary for this OS/CPU into ~/.local/bin
# (override with AMM_INSTALL_DIR). No sudo. Rerun it to update.
set -euo pipefail

case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) echo "error: amm supports macOS and Linux only." >&2; exit 1 ;;
esac

if [ "$os" = darwin ]; then
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then arch=arm64; else arch=x64; fi
else
    if [ "$(uname -m)" = x86_64 ]; then arch=x64; else
        echo "error: amm on Linux is x64 only for now." >&2; exit 1
    fi
fi

dir="${AMM_INSTALL_DIR:-$HOME/.local/bin}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fL "https://github.com/sbrothers7/UMMInstall/releases/latest/download/amm-$os-$arch" -o "$tmp"
chmod +x "$tmp"
mkdir -p "$dir"
mv "$tmp" "$dir/amm"
ln -sf amm "$dir/ammtui"

echo "Installed amm to $dir"
case ":$PATH:" in
    *":$dir:"*) ;;
    *) echo "Add this to your shell profile: export PATH=\"$dir:\$PATH\"" ;;
esac
