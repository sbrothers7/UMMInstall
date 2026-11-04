#!/bin/bash
#
# uninstall.sh — remove the amm CLI (and the ammtui menu alias).
#
#   curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/cli/uninstall.sh | bash
#   ... | bash -s -- --keep-config    # keep ~/.config/amm
#
# Undoes install.sh: removes amm and ammtui from ~/.local/bin (or
# AMM_INSTALL_DIR, or wherever amm is on PATH), the PATH line it added to the
# shell profile, and amm's settings. Mod loaders, mods and the GUI app stay;
# remove a loader first with `amm uninstall` if you want it gone.
set -euo pipefail

keep_config=false
for arg in "$@"; do
    case "$arg" in
        --keep-config) keep_config=true ;;
        *) echo "error: unknown option $arg" >&2; exit 2 ;;
    esac
done

# The folders amm may be in: the one asked for, the installer's default, and
# the one PATH finds it in.
dirs=("${AMM_INSTALL_DIR:-$HOME/.local/bin}")
if found="$(command -v amm 2>/dev/null)" && [ -n "$found" ] && [ "${found#/}" != "$found" ]; then
    dirs+=("$(dirname "$found")")
fi

removed=false
for dir in "${dirs[@]}"; do
    for name in amm ammtui; do
        f="$dir/$name"
        if [ -e "$f" ] || [ -L "$f" ]; then
            rm -f "$f"
            echo "Removed $f"
            removed=true
        fi
    done
done
$removed || echo "amm isn't installed in ${dirs[*]}."

# The installer appends a blank line, a marker comment and an export line.
# Drop exactly those, for each folder, leaving the rest of the profile as is.
for rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || continue
    grep -qxF '# Added by the amm installer' "$rc" || continue
    tmp="$(mktemp)"
    # Through the environment: BSD awk rejects newlines in -v values.
    AMM_DIRS="$(printf '%s\n' "${dirs[@]}")" awk '
        BEGIN { n = split(ENVIRON["AMM_DIRS"], d, "\n"); for (i = 1; i <= n; i++) if (d[i] != "") want["export PATH=\"" d[i] ":$PATH\""] = 1 }
        # Hold a blank line until we know it is not the one before our marker.
        held && $0 == "# Added by the amm installer" { held = 0; marker = 1; next }
        held { print ""; held = 0 }
        marker { marker = 0; if ($0 in want) next; print "# Added by the amm installer" }
        $0 == "" { held = 1; next }
        $0 == "# Added by the amm installer" { marker = 1; next }
        { print }
        END { if (held) print ""; if (marker) print "# Added by the amm installer" }
    ' "$rc" >"$tmp"
    if ! cmp -s "$tmp" "$rc"; then
        # Write in place so a symlinked profile (dotfiles) stays a link.
        cat "$tmp" >"$rc"
        echo "Removed amm from PATH in $rc"
    fi
    rm -f "$tmp"
done

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/amm"
if [ -d "$cfg" ]; then
    if $keep_config; then
        echo "Kept settings in $cfg"
    else
        rm -rf "$cfg"
        echo "Removed settings in $cfg"
    fi
fi

echo "amm is uninstalled. Mod loaders, mods and the GUI app were left in place."
