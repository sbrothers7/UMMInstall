#!/bin/bash
# Checks the loader scripts without touching a real game: pick_mode is
# extracted from the macOS UMM scripts, and the Linux scripts run against a
# fake game folder with stubbed uname/curl. Works on macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

for f in "$ROOT"/macos/*.sh "$ROOT"/linux/*.sh; do bash -n "$f"; done

for s in adofai-umm.sh adofai-umm-uninstall.sh; do
    eval "$(sed -n '/^pick_mode()/,/^}/p' "$ROOT/macos/$s")"
    [ "$(pick_mode "" 2)" = rosetta ] || fail "$s: '' 2"
    [ "$(pick_mode "" 3)" = native ] || fail "$s: '' 3"
    [ "$(pick_mode "" "")" = native ] || fail "$s: '' ''"
    [ "$(pick_mode rosetta 3)" = rosetta ] || fail "$s: rosetta 3"
    [ "$(pick_mode native 2)" = native ] || fail "$s: native 2"
    if pick_mode bogus 3 >/dev/null 2>&1; then fail "$s: bogus accepted"; fi
done

# Fixture zips and stubs.
python3 -c '
import sys, zipfile
d = sys.argv[1]
with zipfile.ZipFile(d + "/ml.zip", "w") as z:
    z.writestr("MelonLoader/x.dll", "x")
    z.writestr("MelonLoader.Bootstrap.so", "x")
with zipfile.ZipFile(d + "/compat.zip", "w") as z:
    z.writestr("Plugins/UMMBridge.dll", "x")
' "$TMP"
mkdir "$TMP/bin"
printf '#!/bin/sh\necho x86_64\n' > "$TMP/bin/uname"
# The curl stub copies a fixture zip to its -o target.
cat > "$TMP/bin/curl" <<'STUB'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift ;; http*) url="$1" ;; esac
    shift
done
case "$url" in
    *UMMCompat*) cp "$FIXTURES/compat.zip" "$out" ;;
    *) cp "$FIXTURES/ml.zip" "$out" ;;
esac
STUB
chmod +x "$TMP/bin/uname" "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export FIXTURES="$TMP"

GAME="$TMP/game"
MANAGED="$GAME/A Dance of Fire and Ice_Data/Managed"
mkdir -p "$MANAGED"
echo orig > "$MANAGED/UnityEngine.CoreModule.dll.bak"

bash "$ROOT/linux/adofai-melonloader.sh" "$GAME" >/dev/null
grep -q 'LD_PRELOAD="MelonLoader.Bootstrap.so' "$GAME/setup_helper.sh" || fail "setup_helper.sh"
[ -x "$GAME/setup_helper.sh" ] || fail "setup_helper.sh not executable"
[ "$(cat "$GAME/MelonLoader/MelonLoader.version")" = 0.7.3 ] || fail "version marker"
[ -d "$GAME/UMMMods" ] || fail "UMMMods"
[ -f "$GAME/Plugins/UMMBridge.dll" ] || fail "UMMCompat"
[ -f "$MANAGED/UnityEngine.CoreModule.dll" ] || fail "CoreModule not restored"

bash "$ROOT/linux/adofai-melonloader-uninstall.sh" "$GAME" >/dev/null
[ ! -e "$GAME/MelonLoader" ] || fail "MelonLoader remains"
[ ! -e "$GAME/setup_helper.sh" ] || fail "setup_helper.sh remains"

if bash "$ROOT/linux/adofai-melonloader.sh" >/dev/null 2>&1; then fail "no-arg install succeeded"; fi

# CLI release: asset names must be the bare binaries, and install.sh must
# install amm plus the ammtui symlink and add it to PATH once (curl stubbed,
# nothing downloaded, HOME sandboxed).
bash -n "$ROOT/cli/install.sh"
targets="$(sed -n '/^  cli:/,$p' "$ROOT/.github/workflows/release-gui.yml" | grep -o 'target: [a-z0-9-]*' | sed 's/target: /amm-/' | sort | tr '\n' ' ')"
[ "$targets" = "amm-darwin-arm64 amm-darwin-x64 amm-linux-x64 " ] || fail "cli targets: $targets"
for t in $targets; do
    echo "$t" | grep -Eq '^amm-(darwin-arm64|darwin-x64|linux-x64)$' || fail "asset name $t"
    case "$t" in *.zip) fail "$t is a zip" ;; esac
done
mkdir "$TMP/bin2" "$TMP/inst" "$TMP/home"
printf '#!/bin/sh\nout=""\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done\nprintf "#!/bin/sh\\necho stub\\n" > "$out"\n' > "$TMP/bin2/curl"
printf '#!/bin/sh\n[ "$1" = -s ] && echo Linux || echo x86_64\n' > "$TMP/bin2/uname"
chmod +x "$TMP/bin2/curl" "$TMP/bin2/uname"
for _ in 1 2; do
    PATH="$TMP/bin2:$PATH" HOME="$TMP/home" SHELL=/bin/bash AMM_INSTALL_DIR="$TMP/inst" \
        bash "$ROOT/cli/install.sh" >/dev/null
done
[ -x "$TMP/inst/amm" ] || fail "amm not installed"
[ -L "$TMP/inst/ammtui" ] || fail "ammtui link"
[ "$(grep -cxF "export PATH=\"$TMP/inst:\$PATH\"" "$TMP/home/.bashrc")" = 1 ] || fail "PATH line in .bashrc"

echo "scripts ok"
