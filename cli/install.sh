#!/bin/bash
#
# install.sh — install the amm CLI (and the ammtui menu alias).
#
#   curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/cli/install.sh | bash
#
# Downloads the latest release binary for this OS/CPU into ~/.local/bin
# (override with AMM_INSTALL_DIR) and puts that folder on PATH via the
# zsh/bash profile. No sudo. Rerun it, or run `amm update`, to update.
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
    *":$dir:"*) exit 0 ;;
esac

# Not on PATH yet: add it to the login shell's profile, once.
line="export PATH=\"$dir:\$PATH\""
case "${SHELL##*/}" in
    zsh) rc="${ZDOTDIR:-$HOME}/.zshrc" ;;
    # macOS terminals start login shells, which skip .bashrc.
    bash) if [ "$os" = darwin ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
    *) echo "Add this to your shell profile: $line"; exit 0 ;;
esac
grep -qsxF "$line" "$rc" || printf '\n# Added by the amm installer\n%s\n' "$line" >> "$rc"
echo "Added $dir to PATH in $rc. Open a new terminal to use amm."
