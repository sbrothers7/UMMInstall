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

echo "scripts ok"
