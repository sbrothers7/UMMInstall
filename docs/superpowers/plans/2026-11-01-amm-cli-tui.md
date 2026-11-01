# amm CLI and TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `amm` (a scriptable CLI) and `ammtui` (a keyboard menu over the same actions) for installing ADOFAI mod loaders and mods on macOS and Linux, sharing one plain-Dart core with the Flutter GUI.

**Architecture:** A new plain-Dart package `core/` (`amm_core`) takes the GUI's non-Flutter code plus the mod/loader logic now inside `AppState`. The GUI depends on it by path. A second package `cli/` (`amm`) holds `bin/amm.dart`, compiled with `dart compile exe`; `ammtui` is the same binary started under that name. Core owns *what* happens (which script and arguments, which folders move, where a zip lands, what gets recorded). Each front end owns the *sequence and wording*: the GUI keeps its localized flows, and the CLI writes its own English flows from the same core calls.

**Tech Stack:** Dart `^3.12.2` (same as `gui/pubspec.yaml`), `package:http`, `package:path`, `package:archive` (core), `package:args` (cli), `package:test` and `package:lints` (dev). Bash for loader scripts. GitHub Actions for CI and releases.

**Spec:** `docs/superpowers/specs/2026-10-31-amm-cli-tui-design.md`

## Global Constraints

- Platforms: macOS and Linux only. On any other OS `amm` prints `amm supports macOS and Linux only.` and exits 1. The GUI's Windows code paths stay as they are.
- Linux: native build only (no Proton), x64 only, method `ml` only.
- Run with no argument, `macos/*.sh` must behave exactly as today: released GUIs download them live from `https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/`.
- Script base URL stays `https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/`. `mods.json` stays at `https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/mods.json`. After merging, `v2` is fast-forwarded to `main` as before.
- Any new `mods.json` field must be added to `STR_FIELDS`/`BOOL_FIELDS` in `.github/scripts/update_mods.py`, which rejects unknown fields.
- CLI release assets are bare binaries named exactly `amm-darwin-arm64`, `amm-darwin-x64`, `amm-linux-x64`. They are never `.zip`, and they go on the same GitHub release (tag `v2.*`) as the GUI zip.
- `list`, `default` and `install` with a loader already present (status) make no network calls.
- `uninstall`, `reinstall` and `mr` confirm first unless `-y`/`--yes` is passed. When stdin is not a terminal and there is no `-y`, they refuse with `Pass -y to confirm without a prompt.` and exit 1.
- Config: `$XDG_CONFIG_HOME/amm/config.json`, else `~/.config/amm/config.json`, shaped `{"default": "ml"}`. A missing or corrupt file means `ml`.
- Install record: `<game folder>/.amm/installed.json`.
- Allowed dependencies: core uses only `http`, `path`, `archive`; cli adds only `args`. No TUI library; use `dart:io` raw mode and ANSI escapes.
- The GUI behaves the same and keeps its `t(en, ko)` wording. Core messages are English and are used only by the CLI and TUI.
- Keep the zip rules from `mod_downloader.dart`: reject entries that resolve outside the extract folder, skip symlinks, merge game-root layouts (`Mods/`, `Plugins/`, `UserData/`, `UserLibs/`) into the game root.
- Work on branch `amm-cli` off `main`. Ask the owner before the first `git push` (CI only runs after a push), and before any tag or release.
- Every commit message ends with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Neither Flutter nor Dart is installed on the dev Mac. Install Dart once with `brew tap dart-lang/dart && brew install dart`. GUI changes are checked by `flutter analyze` in CI (Task 1 adds it), not locally.

## Review Focus

1. **An old GUI runs a changed `macos/adofai-umm*.sh` with no argument.** It must take today's branch: v2 gets Console.exe, anything else gets MacTuiInstaller. Pinned by the `pick_mode` table in `.github/scripts/test_scripts.sh` (Task 3).
2. **stdin isn't a terminal** (piped, CI, `curl | bash` habits) when a command wants to confirm. It must refuse, not hang. Pinned by `confirm refuses without a terminal` (Task 7).
3. **modlist.org or GitHub raw is unreachable.** `search` and `mi` keep working from the source that answered and print one warning line; only both failing is an error. Pinned by `Catalog.load keeps working when one source fails` (Task 5).
4. **A download fails partway through `upgrade`.** The installed mod must be untouched. Pinned by `upgrade keeps the old mod when the download fails` (Task 6).
5. **The game is missing, or its version is unknown.** Commands that need the game say where they looked and exit 1. An unknown macOS version counts as v3, as in the GUI. Pinned by `resolveInstall treats unknown version as v3` (Task 2) and `list without a game exits 1` (Task 7).

---

### Task 1: Extract the core package

Moves the plain-Dart files out of the GUI without changing behavior.

**Files:**
- Create: `core/pubspec.yaml`, `core/analysis_options.yaml` (`include: package:lints/recommended.yaml`), `core/lib/amm_core.dart`, `core/lib/src/net.dart`
- Move (git mv) from `gui/lib/src/` to `core/lib/src/`: `platform/game_paths.dart`, `platform/steam_config.dart`, `install/script_runner.dart`, `install/mod_downloader.dart`, `install/install_scripts.dart`, `mod_registry.dart`
- Create: `core/lib/src/models.dart`, holding `LogLevel`, `InstalledMod` and `ArchivedMod` moved out of `gui/lib/src/models.dart`
- Modify: `gui/lib/src/models.dart` (keeps `Language`, `LoaderType`, `InstallPhase`, `LogEntry`; imports `LogLevel` from core), `gui/lib/src/app_state.dart` and `gui/lib/src/ui/*.dart` imports, `gui/pubspec.yaml` (add `amm_core: {path: ../core}`)
- Move: `gui/test/mod_downloader_test.dart` to `core/test/mod_downloader_test.dart`; the two `Mod` tests in `gui/test/widget_test.dart` to `core/test/mod_registry_test.dart`. Delete `gui/test/widget_test.dart`.
- Create: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release-gui.yml:35`, replacing `flutter test test/mod_downloader_test.dart` with a step that runs `dart pub get && dart test` in `core/`

**Interfaces:**
- Produces: `package:amm_core/amm_core.dart`, which exports every `core/lib/src` file. Later tasks add to it.
- Produces: `http.Client httpClient` in `core/lib/src/net.dart`, a top-level mutable client. Tests assign a `MockClient` from `package:http/testing.dart`. `ModRegistry.fetch`, `ScriptRunner.run` and `ModDownloader._download` switch from `http.get`/`http.Client()` to it.

- [ ] **Step 1:** Install Dart (`brew tap dart-lang/dart && brew install dart`), create branch `amm-cli` from `main`, and write `core/pubspec.yaml`: name `amm_core`, `publish_to: none`, sdk `^3.12.2`, deps `http: ^1.2.0`, `path: ^1.9.0`, `archive: ^4.0.0`, dev deps `test`, `lints`.
- [ ] **Step 2:** Move the files and tests as listed. In the moved tests, replace `package:flutter_test/flutter_test.dart` with `package:test/test.dart` and `package:adofai_mod_installer/src/...` with `package:amm_core/amm_core.dart`.
- [ ] **Step 3:** Run `(cd core && dart pub get && dart test)`. Expected: 7 tests pass (5 downloader, 2 registry).
- [ ] **Step 4:** Fix the GUI imports. Run `(cd core && dart analyze)`. Expected: `No issues found!`. Also check that `grep -rn "src/platform\|src/install\|src/mod_registry" gui/lib` prints nothing.
- [ ] **Step 5:** Write `.github/workflows/ci.yml`: on `push` and `pull_request`. Job `dart` (matrix `ubuntu-latest`, `macos-latest`) uses `dart-lang/setup-dart@v1`, then runs `dart pub get && dart analyze && dart test` in `core/`. Job `gui` (`macos-latest`) uses `subosito/flutter-action@v2` (stable), then runs `flutter pub get && flutter analyze` in `gui/`.
- [ ] **Step 6:** Commit with message `Move the GUI's plain-Dart code into a shared core package`. After the owner OKs the first push, push and confirm both CI jobs pass.

### Task 2: Game facts and method rules

**Files:**
- Create: `core/lib/src/game_state.dart`
- Modify: `core/lib/src/models.dart` (add `Method`), `core/lib/src/platform/game_paths.dart`
- Test: `core/test/game_state_test.dart`, `core/test/game_paths_test.dart`

**Interfaces:**
- Produces in `models.dart`: `enum Method { ml, native, rosetta }` with `static Method? parse(String s)`, which matches `name` case-insensitively.
- Produces in `game_paths.dart`:
  - `static void overrideGamePath(String? path)` sets the cached game path (for tests).
  - `static int? unityMajorToGameMajor(List<int> header)` finds the first `\d{4}\.\d+\.\d+[a-z]\d+` in the bytes read as latin1, then returns `3` if it starts with `6` and `2` if it starts with `20`, else null.
  - `static Future<int?> detectGameMajor()`: on macOS, the leading integer of `detectGameVersion()`; on Linux, `unityMajorToGameMajor` over the first 4096 bytes of `<game>/A Dance of Fire and Ice_Data/globalgamemanagers`; null when unreadable.
- Produces in `game_state.dart`:
  - `enum LoaderKind { none, melonLoader, umm }`
  - `class GameFacts { String os; bool found; String gamePath; String? version; int? major; bool appleSilicon; bool hasArm64Slice; LoaderKind loader; bool get isV2 => major == 2; static Future<GameFacts> detect(); }`. It has a plain const-style constructor with named args for tests. `detect()` calls `GamePaths.detect()` and then the existing getters.
  - `sealed class Decision`, `class Proceed extends Decision { Method method; String? confirm; }`, `class Refuse extends Decision { String message; }`
  - `Decision resolveInstall(GameFacts f, {Method? requested, required Method fallback})`
  - `Method inferMethod({required LoaderKind loader, required bool isV2, required bool appleSilicon, required bool hasArm64Slice})`
  - `List<String> missingLoaderFiles(GameFacts f)`

**Rules for `resolveInstall`**, where `m = requested ?? fallback`, checked in this order:
1. `os` is neither `macos` nor `linux`: Refuse `amm supports macOS and Linux only.`
2. Linux: if `m != ml`, Refuse with a message containing `Linux` and `--ml`. Otherwise Proceed(ml).
3. macOS with `major == 2`: if `requested` is `ml` or `native`, Refuse with a message containing `untested on game v2`. Otherwise Proceed(rosetta). The fallback is ignored on v2.
4. macOS with any other or unknown major:
   - `native` on Intel: Refuse, containing `Apple Silicon`.
   - `ml` or `native` on Apple Silicon without the arm64 slice: Refuse, containing `steam://validate/977950`.
   - `rosetta`: Proceed with `confirm` containing `untested on game v3`. On Apple Silicon, also say that the arm64 strip means verifying game files in Steam before `--ml`/`--native` work again.
   - Anything else: Proceed(m) with no confirm.

**`inferMethod`** *(plan's call: Intel added, since native can't exist there)*: `melonLoader` gives `ml`. `umm` gives `rosetta` when `isV2 || !appleSilicon || !hasArm64Slice`, otherwise `native`. `none` gives `ml` (callers only use it when a loader is present).

**`missingLoaderFiles`**: for `melonLoader`, those of `MelonLoader`, `setup_helper.sh`, `UMMMods` and the bootstrap that are absent under `gamePath`. The bootstrap is `MelonLoader.Bootstrap.dylib` on macOS and `MelonLoader.Bootstrap.so` on Linux. For other loaders, return `[]`.

- [ ] **Step 1: Write the failing tests.** In `game_state_test.dart`, write a `facts({...})` helper (defaults: macos, found, major 3, appleSilicon, hasArm64Slice, loader none). Add one `test` per row:
  - `linux refuses native`: `resolveInstall(facts(os:'linux'), requested: Method.native, fallback: Method.ml)` is a Refuse whose message contains `--ml`.
  - `linux uses ml`: os linux, fallback ml, gives Proceed(ml).
  - `v2 forces rosetta over default`: major 2, fallback ml, gives Proceed(rosetta) with confirm null.
  - `v2 refuses explicit ml`: major 2, requested ml, gives a Refuse containing `untested on game v2`.
  - `intel refuses native on v3`: appleSilicon false, requested native, gives a Refuse containing `Apple Silicon`.
  - `stripped slice refuses ml`: hasArm64Slice false, fallback ml, gives a Refuse containing `steam://validate/977950`.
  - `rosetta on v3 asks to confirm`: requested rosetta gives Proceed(rosetta) with confirm containing `untested on game v3`.
  - `resolveInstall treats unknown version as v3`: major null, fallback ml, gives Proceed(ml).
  - `inferMethod` cases: (umm, v2) gives rosetta; (umm, v3, AS, slice) gives native; (umm, v3, AS, no slice) gives rosetta; (umm, v3, Intel) gives rosetta; (melonLoader) gives ml.
  - `missingLoaderFiles lists absent ml files`: a temp dir holding only `MelonLoader/` returns a list that includes `setup_helper.sh`.

  In `game_paths_test.dart`:
  - `unityMajorToGameMajor` on bytes `[0,0,0,0x16, ...latin1('6000.0.58f2'), 0]` returns 3.
  - On `'2022.3.62f1'` it returns 2.
  - On `'no version here'` it returns null.
- [ ] **Step 2:** Run `(cd core && dart test test/game_state_test.dart test/game_paths_test.dart)`. Expected: FAIL, because `resolveInstall` and `unityMajorToGameMajor` are undefined.
- [ ] **Step 3:** Implement the interfaces above.
- [ ] **Step 4:** Run the same command. Expected: all pass.
- [ ] **Step 5:** Commit with message `Add game facts and install-method rules to core`.

### Task 3: Loader scripts take a method; Linux MelonLoader scripts

**Files:**
- Modify: `macos/adofai-umm.sh`, `macos/adofai-umm-uninstall.sh`
- Create: `linux/adofai-melonloader.sh`, `linux/adofai-melonloader-uninstall.sh`, `.github/scripts/test_scripts.sh`
- Modify: `core/lib/src/install/install_scripts.dart`, `core/lib/src/install/script_runner.dart`, `gui/lib/src/app_state.dart`, `.github/workflows/ci.yml` (run `bash .github/scripts/test_scripts.sh` in the `dart` job)
- Test: `core/test/install_scripts_test.dart`

**Interfaces:**
- Consumes: `Method`, `inferMethod`, `LoaderKind` (Task 2); `AmmRecord` comes in Task 4, so this task's GUI change writes no record yet.
- Produces:
  - `class ScriptCall { final String url; final List<String> args; const ScriptCall(this.url, [this.args = const []]); }` with `==`/`hashCode` for tests.
  - `InstallScripts.install(Method m, {String? os, String? gamePath})` and `InstallScripts.uninstall(Method m, {String? os, String? gamePath})`, both returning `ScriptCall?`. `os` defaults to `Platform.operatingSystem` and `gamePath` to `GamePaths.gamePath`. `installUrl`/`uninstallUrl` are removed.
  - `ScriptRunner.run({required ScriptCall call, required onLog, required onSubtitle})`, which starts `/bin/bash <tmp> ...call.args`.

**Mapping** (paths under the v2 base URL):

| os | method | install | uninstall |
|---|---|---|---|
| macos | ml | `macos/adofai-melonloader.sh` | `macos/adofai-melonloader-uninstall.sh` |
| macos | native/rosetta | `macos/adofai-umm.sh [method]` | `macos/adofai-umm-uninstall.sh [method]` |
| linux | ml | `linux/adofai-melonloader.sh [gamePath]` | `linux/adofai-melonloader-uninstall.sh [gamePath]` |
| linux | others | null | null |
| windows | ml | `windows/adofai-melonloader.ps1` (unchanged) | `windows/adofai-melonloader-uninstall.ps1` |

**macOS scripts:** add this function to both UMM scripts after `GAME_MAJOR` is set, and replace `if [ "$GAME_MAJOR" = "2" ]; then` with `if [ "$MODE" = "rosetta" ]; then`. Change nothing else.

```bash
# $1: method argument (rosetta|native|empty), $2: game major version.
# No argument keeps the old behavior: v2 -> rosetta, anything else -> native.
pick_mode() {
    case "$1" in
        rosetta|native) echo "$1" ;;
        "") if [ "$2" = "2" ]; then echo rosetta; else echo native; fi ;;
        *) echo "error:Unknown method '$1' (expected rosetta or native)." >&2; return 1 ;;
    esac
}
MODE="$(pick_mode "${1:-}" "$GAME_MAJOR")"
```

**Linux install script** (`$1` = game folder; uses the same line protocol as the macOS scripts):
- Exit with `error:` lines when:
  - `$1` is missing, or `$1/A Dance of Fire and Ice_Data` isn't a directory;
  - `uname -m` isn't `x86_64`;
  - `curl` or `unzip` isn't installed (`error:unzip is required — install it with your package manager.`).
- Restore `UnityEngine.CoreModule.dll` and `UnityEngine.dll` from `.bak`/`.original` in `$1/A Dance of Fire and Ice_Data/Managed`, and remove `Managed/UnityModManager`. This is the same loop as the macOS script.
- Remove prior artifacts: `MelonLoader`, `MelonLoader.Bootstrap.so`, `setup_helper.sh`, `NOTICE.txt`.
- Download `https://github.com/kkorenn/MelonLoader/releases/download/v0.7.3/MelonLoader.Linux.x64.zip` to a `mktemp` file and run `unzip -o -q` into `$1`. Write `0.7.3` to `$1/MelonLoader/MelonLoader.version`.
- Write `$1/setup_helper.sh` and `chmod +x` it. Per MelonWiki's Linux native instructions, put the game folder on `LD_LIBRARY_PATH` and name the bootstrap by file name only in `LD_PRELOAD`:
  ```bash
  #!/bin/bash
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export LD_LIBRARY_PATH="$DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LD_PRELOAD="MelonLoader.Bootstrap.so${LD_PRELOAD:+:$LD_PRELOAD}"
  exec "$@"
  ```
  Launch options then use the same `"<game>/setup_helper.sh" %command%` form as macOS, so `SteamConfig` needs no change.
- `mkdir -p` `UMMMods` and `Mods`. Download `https://github.com/modlist-org/UMMCompat/releases/latest/download/UMMCompat.zip` and unzip it into `$1`. Print `ok:UMMCompat installed.`, or an `error:` line and continue, as macOS does. End with `ok:MelonLoader 0.7.3 installed.`

**Linux uninstall script:** check `$1` the same way, then remove `MelonLoader`, `MelonLoader.Bootstrap.so`, `setup_helper.sh`, `NOTICE.txt`, `version.dll`, `winhttp.dll` (each `rm -rf` with an `  rm <name>` line). End with `ok:MelonLoader uninstalled.`

**GUI** (`app_state.dart`):
- Install: `ScriptCall` comes from `InstallScripts.install(_guiMethod(selectedLoader))`, where `_guiMethod` maps `melonLoader` to `ml` and `umm` to `isGameV2 ? rosetta : native`. With today's scripts this is the same branch as no argument.
- Uninstall: uses `InstallScripts.uninstall(inferMethod(loader: …, isV2: isGameV2, appleSilicon: GamePaths.isAppleSilicon(), hasArm64Slice: GamePaths.hasArm64Slice()))`.
- Migration: uses `uninstall(inferMethod(...))` and `install(Method.ml)`.

- [ ] **Step 1: Write the failing tests.**
  - `install_scripts_test.dart`: one `expect` per mapping row, passing `os:` and `gamePath: '/g'`. For example, `InstallScripts.install(Method.rosetta, os: 'macos')` equals `ScriptCall('${base}macos/adofai-umm.sh', ['rosetta'])`, and `InstallScripts.install(Method.native, os: 'linux')` is null.
  - `test_scripts.sh` (bash, `set -euo pipefail`, prints `scripts ok`):
    - For each of the two UMM scripts, extract `pick_mode` with `sed -n '/^pick_mode()/,/^}/p'`, `eval` it, then assert: `("" 2)` gives `rosetta`; `("" 3)` and `("" "")` give `native`; `(rosetta 3)` gives `rosetta`; `(native 2)` gives `native`; `(bogus 3)` fails.
    - Run `bash -n` on all six `.sh` files.
    - Build a fake game in `mktemp -d`, holding `A Dance of Fire and Ice_Data/Managed/UnityEngine.CoreModule.dll.bak`.
    - Put stubs first on `PATH`: `uname` echoing `x86_64`, and `curl` that copies a fixture zip to its `-o` argument. The fixtures are made with `python3 -c 'import zipfile…'`; the MelonLoader one holds `MelonLoader/x.dll` and `MelonLoader.Bootstrap.so`, the UMMCompat one holds `Plugins/UMMBridge.dll`.
    - Run `linux/adofai-melonloader.sh "$GAME"` and assert that `setup_helper.sh` contains `LD_PRELOAD="MelonLoader.Bootstrap.so`, that `MelonLoader/MelonLoader.version` is `0.7.3`, that `UMMMods/` and `Plugins/UMMBridge.dll` exist, and that `UnityEngine.CoreModule.dll` was restored.
    - Run the uninstall script and assert that `MelonLoader/` and `setup_helper.sh` are gone.
- [ ] **Step 2:** Run `(cd core && dart test test/install_scripts_test.dart)` and `bash .github/scripts/test_scripts.sh`. Expected: both FAIL (`ScriptCall` undefined; `pick_mode` not found).
- [ ] **Step 3:** Implement the scripts, `ScriptCall`, `InstallScripts`, `ScriptRunner` and the GUI change.
- [ ] **Step 4:** Rerun both commands. Expected: tests pass and `scripts ok`. Check that `git diff main -- macos/` shows only the `pick_mode` block and the changed `if` line in each UMM script.
- [ ] **Step 5:** Commit with message `Let UMM scripts take a method and add Linux MelonLoader scripts`. Tell the owner the Linux flow still needs a real run on a Linux Steam install (Steam Linux Runtime with `LD_PRELOAD` can't be checked here).

### Task 4: Mod store, install record, launch-option status

**Files:**
- Create: `core/lib/src/mod_store.dart`, `core/lib/src/record.dart`
- Modify: `core/lib/src/platform/steam_config.dart`, `core/lib/src/install/mod_downloader.dart` (use `ModStore.moveEntity`; delete its `_moveInto`/`_copyRecursive`), `gui/lib/src/app_state.dart`
- Test: `core/test/mod_store_test.dart`, `core/test/record_test.dart`, `core/test/steam_config_test.dart`

**Interfaces:**
- Produces in `mod_store.dart`. These are moved from `AppState` with behavior unchanged; the GUI calls them in place of its private copies.
  - `class ModStore`, with static methods:
    - `List<InstalledMod> scanInstalled()`
    - `List<ArchivedMod> scanArchived()`
    - `void delete(String path)`
    - `void archive(InstalledMod mod)`
    - `void restore(ArchivedMod a)`
    - `void deleteArchived(ArchivedMod a)`
    - `List<String> findUmmMods(String dir)`: folder names in `dir` that contain an `info.json` (any case), sorted.
    - `List<String> moveMods(List<String> names, String from, String to, {void Function(String name, Object error)? onError})`: returns the names it moved.
    - `String? infoField(String folder, String key)`: reads `Info.json`/`info.json`.
    - `void moveEntity(String src, String dst)`
- Produces in `record.dart`:
  - `class RecordEntry { final String source; final String? version; final List<String> paths; }`. `source` is `'mods.json'` or `'modlist.org'`; `paths` are relative to the game root and use `/`.
  - `class AmmRecord`:
    - Fields: `Method? method` and `final Map<String, RecordEntry> mods`.
    - `static AmmRecord load(String gameRoot)`: a missing file gives an empty record. A corrupt one is renamed to `installed.json.bad`, and an empty record is returned.
    - `void save(String gameRoot)`: creates `.amm/` and writes `{"method": "ml", "mods": {"quartz": {"source": "mods.json", "version": "2.1.1", "paths": ["UMMMods/Quartz"]}}}`.
    - `void movePaths(String fromDir, String toDir, List<String> names)`: rewrites `fromDir/<name>` prefixes to `toDir/<name>`.
    - `RecordEntry? ownerOf(String relPath)`
- Produces in `steam_config.dart`:
  - `static String? readLaunchOptions(String vdfText)`: the unescaped value for app 977950, or null.
  - `static bool? launchOptionsSet()`: null when there is no `localconfig.vdf`, true when any config's value contains `setup_helper.sh`.

**GUI:**
- Replace the private scan/archive/restore/delete/find/move/display-name helpers in `AppState` with `ModStore` calls. Keep `moveMigratableMods`'s log wording.
- After a successful install, uninstall or migration, update the method record with `AmmRecord.load(root)..method = m..save(root)` (null after uninstall).

- [ ] **Step 1: Write the failing tests.**
  - `record_test`:
    - `round-trips method and mods`.
    - `corrupt file becomes empty and is kept as .bad`.
    - `movePaths rewrites Mods/X to UMMMods/X`.
  - `mod_store_test` (temp game via `GamePaths.overrideGamePath`):
    - `findUmmMods finds folders with Info.json only`: a `Mods/` holding `A/Info.json`, `B/x.dll` and `c.dll` gives `['A']`.
    - `moveMods moves and reports`.
    - `archive then restore puts the mod back`.
  - `steam_config_test`: `readLaunchOptions` on a minimal VDF string, `"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "977950" { "LaunchOptions" "\"/g/setup_helper.sh\" %command%" } } } } } }`, gives `"/g/setup_helper.sh" %command%`. With no `977950` block, it gives null.
- [ ] **Step 2:** Run `(cd core && dart test)`. Expected: the new tests FAIL.
- [ ] **Step 3:** Implement the interfaces and the GUI delegation.
- [ ] **Step 4:** Run `(cd core && dart test && dart analyze)`. Expected: all pass, no issues.
- [ ] **Step 5:** Commit with message `Move mod storage into core and add the install record`.

### Task 5: Catalog (slugs, modlist.org, merge)

**Files:**
- Modify: `mods.json`, `.github/scripts/update_mods.py`, `core/lib/src/mod_registry.dart`
- Create: `core/lib/src/modlist.dart`, `core/lib/src/catalog.dart`
- Test: `core/test/catalog_test.dart`, `core/test/modlist_test.dart`; the existing `python3 .github/scripts/update_mods.py selftest`

**Interfaces:**
- `mods.json` gets a `slug` right after each `id`. Write it with the bot's format: `json.dump(indent=2, ensure_ascii=False)` plus a trailing newline.

  | id | slug |
  |---|---|
  | AdofaiTweaks | adofaitweaks |
  | TUFHelper | tufhelper |
  | Bismuth | bismuth |
  | Sapphire | sapphire |
  | Quartz | quartz |
  | JipperResourcePack | jrp |
  | PACL2 | pacl2 |
  | TogetherBootstrap | togetherbootstrap |
  | YouTubeStream | youtubestream |
  | KeyboardChatterBlocker | keyboardchatterblocker |
  | KeyLimiter | keylimiter |
  | EnhancedEffectRemover | enhancedeffectremover |
  | XPerfect | xperfect |
  | DesyncFix | desyncfix |
  | BetterCalibration | bettercalibration |

- `update_mods.py`: add `slug` to `STR_FIELDS`. In `validate`, require `slug`, require it to match `^[a-z0-9][a-z0-9._-]*$`, and reject duplicates.
- `Mod` gains `final String slug` (falls back to `id.toLowerCase()` when absent), `final String? version` and `final String? versionMelon`. It also gets `String? resolvedVersion({required bool isGameV2, required bool isMelonLoader})`, which mirrors `resolvedUrl`: Melon with `urlMelon` gives `versionMelon`; v2 with `urlV2` gives null (pinned, untracked); otherwise `version`.
- `modlist.dart`:
  - `class ModlistMod { final String slug, name, summary; final String? version; final List<String> dependencies; final Set<String> loaders; factory ModlistMod.fromJson(Map<String, dynamic> j); }`
    - `version` is `latestVersion.version`.
    - `loaders` holds the non-null `latestVersion.files[].loader` values; an empty set means the file works with any loader.
  - `class ModlistClient`:
    - `static const base = 'https://modlist.org/api/mods'`
    - `static Future<List<ModlistMod>> fetchAll()` requests `$base?game=adofai&limit=50&page=N` until `page >= pagination.totalPages`, with an 8s timeout per request.
    - `static Uri downloadUri(String slug, {required String loader, required String platform, String? gameVersion})` builds `$base/<slug>/download?loader=&platform=&gameVersion=`, leaving out `gameVersion` when null.
- `catalog.dart`:
  - `enum Source { modsJson, modlist }`, with `String get label` giving `'mods.json'` or `'modlist.org'`.
  - `class CatalogEntry { String slug; String name; String summary; Source source; Mod? ours; ModlistMod? theirs; bool get jalib; List<String> get dependencies; bool visibleOn(bool? isV2); }`
    - `name` is `ours.id` when ours exists. `summary` and `dependencies` come from `theirs` when present.
    - `visibleOn`: null means true. For ours, use its `v2`/`v3` flags. Modlist-only entries are always visible.
  - `class Catalog { final List<CatalogEntry> entries; final List<String> warnings; }`, with:
    - `static Catalog merge(List<Mod> ours, List<ModlistMod> theirs)`: on an equal slug (case-insensitive) ours wins, and `theirs` stays attached.
    - `static Future<Catalog> load()`: fetches both at once. A failure becomes a warning such as `modlist.org unreachable: <error>` or `mods.json unreachable: <error>`. If both fail, it throws `ModRegistryException`.
    - `CatalogEntry? find(String slug)`: case-insensitive.
    - `List<CatalogEntry> search(String query)`: case-insensitive substring match on slug, name and summary. An empty query returns everything, sorted by slug.

- [ ] **Step 1: Write the failing tests.**
  - `modlist_test`:
    - `fromJson reads version, deps and loaders`, using a trimmed copy of the real `quartz` object (`latestVersion.files` with loaders `melonloader` and `umm`, so the set is `{melonloader, umm}`).
    - `fetchAll follows pagination` (MockClient answering pages 1 and 2 with `totalPages: 2`).
    - `downloadUri omits null gameVersion`.
  - `catalog_test`:
    - `ours wins on slug collision`: ours `Quartz`/`quartz` plus theirs `quartz` gives one entry with source `modsJson` and `theirs` set.
    - `find is case-insensitive` (`find('Quartz')`).
    - `search matches summary`.
    - `visibleOn hides v2:false on v2`.
    - `Catalog.load keeps working when one source fails`: MockClient returns 500 for modlist.org and a valid mods.json, giving `entries` from ours and one warning that starts with `modlist.org`.
    - `Catalog.load throws when both fail`.
  - Extend `update_mods.py selftest`: a missing slug, an uppercase slug and a duplicate slug each produce a validation error.
- [ ] **Step 2:** Run `(cd core && dart test test/catalog_test.dart test/modlist_test.dart)` and `python3 .github/scripts/update_mods.py selftest`. Expected: FAIL.
- [ ] **Step 3:** Implement the above, and add the slugs to `mods.json` with a one-off Python snippet that inserts `slug` after `id`.
- [ ] **Step 4:** Rerun the step 2 commands, plus `python3 .github/scripts/update_mods.py check`. Expected: all pass, and `mods.json ok (15 mods)`.
- [ ] **Step 5:** Commit with message `Add mod slugs and a catalog merging mods.json with modlist.org`.

### Task 6: Mod operations (install, remove, upgrade)

**Files:**
- Create: `core/lib/src/mod_ops.dart`
- Modify: `core/lib/src/install/mod_downloader.dart`, `gui/lib/src/app_state.dart` (record GUI mod installs)
- Test: `core/test/mod_ops_test.dart`, `core/test/mod_downloader_test.dart`

**Interfaces:**
- Consumes: `Catalog`, `CatalogEntry`, `ModlistClient.downloadUri` (Task 5); `AmmRecord`, `RecordEntry`, `ModStore` (Task 4); `httpClient` (Task 1).
- `ModDownloader` changes:
  - `static Future<Uint8List> download(String url, {void Function(double)? onProgress})` is now public (was `_download`). On status ≥ 400 it reads the body; if the JSON has `statusMessage`, it throws `ModDownloadException('HTTP <code>: <statusMessage>')`, otherwise `'HTTP <code>'`.
  - `static List<String> installBytes(List<int> bytes, {required String modId, required String gameRoot, required String modsDir, bool melonNative = false})` returns the absolute path of each top-level item it placed:
    - game-root layout: each merged child, such as `<game>/Mods/X.dll`;
    - a single folder: `<modsDir>/<folder>`;
    - loose files: `<modsDir>/<modId>`;
    - loose files with `melonNative`: each file directly in `modsDir`, not wrapped.
  - `install(...)` returns that same list.
- `mod_ops.dart`:
  - `class ModTarget { final String gameRoot; final bool isV2; final String? gameVersion; final bool melon; final String platform; }`, where `platform` is `'macos'` or `'linux'`.
  - `class ModOpsException implements Exception { final String message; }`
  - `class InstallPlan { final List<CatalogEntry> order; final List<String> missing; }`
  - `class Upgrade { final CatalogEntry entry; final String? from; final String to; final List<String> oldPaths; }`
  - `class UpgradeScan { final List<Upgrade> upgrades; final List<String> unknown; }`
  - `class ModOps`, with static methods:
    - `InstallPlan plan(Catalog c, List<String> slugs, AmmRecord r)`: dependencies first (depth-first, no duplicates). It skips dependencies already in `r`, always includes the requested slugs, and puts unknown slugs (requested or dependency) in `missing`.
    - `Future<RecordEntry> install(CatalogEntry e, ModTarget t, {void Function(double)? onProgress})`
    - `List<String> remove(String slug, AmmRecord r, String gameRoot, {bool keep = false})`: returns the relative paths removed, and throws `ModOpsException('No installed mod matches "<slug>".')` when none match.
    - `UpgradeScan upgrades(Catalog c, AmmRecord r, List<InstalledMod> onDisk, ModTarget t)`
    - `Future<RecordEntry> upgrade(Upgrade u, ModTarget t, {void Function(double)? onProgress})`

**Rules:**
- `install` refuses `jalib` entries: `<slug> depends on JALib, which is broken right now.` It also refuses entries where `!e.visibleOn(t.isV2)`: `<slug> isn't available for game v<2|3>.`
- **Source for `ours`:**
  - URL is `ours.resolvedUrl(isGameV2: t.isV2, isMelonLoader: t.melon)`.
  - `modsDir` is `<game>/UMMMods` when `t.melon`, else `<game>/Mods`; `melonNative` is false.
  - Version is `ours.resolvedVersion(...)`.
- **Source for modlist-only entries**, with `L = theirs.loaders`:
  - `t.melon` and `L` contains `melonloader`: request loader `melonloader`, `modsDir` `<game>/Mods`, `melonNative: true`.
  - `t.melon` and (`L` is empty or contains `umm`): request `umm`, `modsDir` `<game>/UMMMods`.
  - `!t.melon` and `L` is non-empty without `umm`: throw `<slug> needs MelonLoader. Switch with \`amm reinstall --ml\`.`
  - `!t.melon` otherwise: request `umm`, `modsDir` `<game>/Mods`.
  - The URL is `downloadUri(slug, loader:, platform: t.platform, gameVersion: t.gameVersion)`. Version is `theirs.version`.
- The `RecordEntry` holds the source label, the version and the placed paths made relative to `gameRoot`.
- `remove`:
  - With a record entry, it acts on those paths.
  - Otherwise it matches `ModStore.scanInstalled()` items whose basename without `.dll` equals the slug (case-insensitive), or whose `Info.json` `Id` does.
  - `keep` archives through `ModStore.archive`; otherwise it calls `ModStore.delete`.
  - It drops the record entry.
- `upgrades`:
  - Recorded entries: for each one with a version, find its catalog entry and resolve its source version. When that version is non-null and differs from the recorded one after stripping a leading `v`, it's an upgrade. Add the comment `// ponytail: "differs" not "newer"; catalog is the source of truth`.
  - Unrecorded folders on disk: match the `Info.json` `Id` (case-insensitive) against `ours.id`, `theirs.name` or `slug`, and compare against the `Info.json` `Version`.
  - Unmatched folders go in `unknown` by folder name.
  - Entries whose resolved version is null are never offered.
- `upgrade`: download first; only after that succeeds, delete `oldPaths` and run `installBytes`. If the download throws, nothing on disk changes.

**GUI:** in `_runInstall`, after each successful `ModDownloader.install`, record `RecordEntry(source: 'mods.json', version: mod.resolvedVersion(...), paths: <relative>)` under `mod.slug`. Save the record once after the loop.

- [ ] **Step 1: Write the failing tests.**
  - `mod_downloader_test`:
    - Extend the three layout tests to assert the returned paths.
    - Add `melonNative puts loose dlls straight into Mods`: `{'X.dll': 'a'}` with `modsDir: <game>/Mods` and `melonNative: true` gives a `<game>/Mods/X.dll` file and returns `[<game>/Mods/X.dll]`.
    - Add `download surfaces modlist statusMessage`: MockClient 404 with body `{"statusMessage":"Requested version has no umm macos download link."}` throws a message containing that text.
  - `mod_ops_test` (temp game; MockClient serving zip bytes by URL):
    - `plan orders dependencies first`: theirs `overlayer-module-adofai` depends on `overlayer`, so the order is `[overlayer, overlayer-module-adofai]`.
    - `plan skips recorded dependencies`.
    - `plan reports unknown slugs`.
    - `install records relative paths and version`.
    - `install refuses jalib`.
    - `install refuses a v2:false mod on v2`.
    - `ml-only modlist mod refused on UMM`.
    - `ml install of ml-native mod requests melonloader and lands in Mods`: assert that the requested URL has `loader=melonloader`.
    - `remove deletes recorded paths and drops the entry`.
    - `remove --keep archives`.
    - `remove matches unrecorded folder by name`.
    - `upgrades offers differing version only`.
    - `upgrade keeps the old mod when the download fails`: MockClient 500 throws, and the old folder still exists with the old record.
- [ ] **Step 2:** Run `(cd core && dart test test/mod_ops_test.dart test/mod_downloader_test.dart)`. Expected: FAIL.
- [ ] **Step 3:** Implement the above and the GUI recording.
- [ ] **Step 4:** Run `(cd core && dart test && dart analyze)`. Expected: all pass, no issues.
- [ ] **Step 5:** Commit with message `Add mod install, remove and upgrade operations to core`.

### Task 7: CLI skeleton: parsing, config, output, `default`, `list`, `search`

**Files:**
- Create: `cli/pubspec.yaml` (name `amm`; deps `amm_core: {path: ../core}`, `args: ^2.5.0`, `path: ^1.9.0`; dev `test`, `lints`), `cli/analysis_options.yaml`, `cli/bin/amm.dart`, `cli/lib/src/cli.dart`, `cli/lib/src/context.dart`, `cli/lib/src/out.dart`, `cli/lib/src/config.dart`, `cli/lib/src/mod_commands.dart`
- Modify: `.github/workflows/ci.yml` (run `dart pub get && dart analyze && dart test` in `cli/` too)
- Test: `cli/test/cli_test.dart`, `cli/test/out_test.dart`, `cli/test/config_test.dart`, `cli/test/mod_commands_test.dart`

**Interfaces:**
- `config.dart`: `class Config { Method defaultMethod; static String path({Map<String, String>? env}); static Config load({Map<String, String>? env}); void save({Map<String, String>? env}); }`. `env` defaults to `Platform.environment`.
- `out.dart`: `class Out { Out({StringSink? sink, bool color = false, bool interactive = false, String? Function()? readLine}); factory Out.std(); void log(LogLevel level, String msg); void subtitle(String s); void line(String s); bool confirm(String question, {required bool yes}); }`
  - `Out.std()` uses stdout. Color is on when `stdout.hasTerminal`, interactivity when `stdin.hasTerminal`, and reading uses `stdin.readLineSync`.
  - Colors: ok green, error red, detail dim. Subtitles are bold.
  - `confirm`: with `yes`, returns true. When not interactive, prints `Pass -y to confirm without a prompt.` and returns false. Otherwise it asks `<question> [y/N] ` and returns true only for `y`/`yes`.
- `context.dart`: `typedef RunScript = Future<int> Function({required ScriptCall call, required void Function(LogLevel, String) onLog, required void Function(String) onSubtitle});`, and `class Ctx { final Out out; final Config config; final Future<GameFacts> Function() facts; final RunScript runScript; final Future<Catalog> Function() catalog; final bool yes; }`. Its defaults are `Out.std()`, `Config.load()`, `GameFacts.detect`, `ScriptRunner.run` and `Catalog.load`.
- `cli.dart`:
  - `List<String> normalize(List<String> argv)`: maps the first token `-l` to `list`, `-s` to `search` and `mi` to `modinstall`.
  - `Future<int> runCli(List<String> argv, {Ctx Function(bool yes)? makeCtx})`
    - Checks the OS (rule 1 of Task 2's message) and exits 1 elsewhere.
    - Parses with `package:args`: one `ArgParser` per command, with global flags `-y/--yes` and `-h/--help`.
    - Exit codes: 0 success, 1 failure or refusal, 2 usage error (unknown command or flag, or more than one method flag). Usage text goes to stdout for `help`/no args and to stderr for errors.
    - Commands: `install`, `reinstall`, `uninstall`, `default`, `list`, `search`, `modinstall`, `mr`, `upgrade`, `tui`, `help`.
    - Method flags `--ml`/`--native`/`--rosetta` apply to install and reinstall; `--keep` applies to mr.
- `bin/amm.dart`: `main(args)` exits with `runCli(args)`. When `p.basenameWithoutExtension(Platform.executable) == 'ammtui'` it runs `runTui` instead; that is a stub returning 0 until Task 10.
- `mod_commands.dart`, part 1:
  - `Future<int> setDefault(Ctx c, String? value)`:
    - No value prints `default: <m>`.
    - An invalid value is a usage error (exit 2).
    - On Linux, values other than `ml` are refused (exit 1).
    - Otherwise it saves and prints `default: <m>`.
  - `Future<int> list(Ctx c)`:
    - When the game isn't found, prints `ADOFAI not found (looked in <path>).` and exits 1.
    - Otherwise prints one line per `ModStore.scanInstalled()` item: name, version (record's, else `Info.json` `Version`, else `-`), folder (`Mods`/`UMMMods`), and source (record's label, else `-`).
    - Then, if there are any, `<n> archived (restore them in the GUI)`.
    - No network.
  - `Future<int> search(Ctx c, String query)`:
    - Loads the catalog and prints each warning as an info line.
    - Filters by `visibleOn(facts.found ? facts.isV2 : null)` and prints `slug  version  source  loaders  name — summary`. `loaders` is `any`, `ml`, `umm` or `ml,umm`. JALib entries get a suffix `  [broken: needs JALib]`.
    - No results prints `No mods match "<query>".` and exits 0.

- [ ] **Step 1: Write the failing tests.**
  - `cli_test`:
    - `normalize maps -l, -s, mi`.
    - `two method flags is a usage error` (exit 2).
    - `unknown command exits 2`.
  - `config_test`:
    - `default is ml when file missing`.
    - `save then load round-trips` (env with `XDG_CONFIG_HOME` set to a temp dir).
    - `path uses XDG_CONFIG_HOME`.
  - `out_test`:
    - `confirm refuses without a terminal`: `interactive: false`, `yes: false` returns false, and the sink contains `Pass -y`.
    - `confirm accepts y`.
    - `confirm with yes skips the prompt`.
  - `mod_commands_test`, with a temp game, a fake `facts` and a fake `catalog`:
    - `list without a game exits 1`: the output contains `ADOFAI not found`.
    - `list shows recorded version and source`.
    - `search marks JALib mods broken`.
    - `default refuses native on linux`: facts os `linux` gives exit 1.
- [ ] **Step 2:** Run `(cd cli && dart pub get && dart test)`. Expected: FAIL.
- [ ] **Step 3:** Implement the above.
- [ ] **Step 4:** Run `(cd cli && dart test && dart analyze)`, then `dart run bin/amm.dart -l` on the dev Mac. Expected: tests pass, and `-l` prints the real mod list, or `ADOFAI not found` if the game isn't installed.
- [ ] **Step 5:** Commit with message `Add the amm CLI skeleton with default, list and search`.

### Task 8: CLI loader commands (`install`, `reinstall`, `uninstall`)

**Files:**
- Create: `cli/lib/src/loader_commands.dart`
- Modify: `cli/lib/src/cli.dart` (wire the commands)
- Test: `cli/test/loader_commands_test.dart`

**Interfaces:**
- Consumes: `resolveInstall`, `inferMethod`, `missingLoaderFiles`, `GameFacts` (Task 2); `InstallScripts`, `ScriptCall` (Task 3); `AmmRecord`, `ModStore`, `SteamConfig.launchOptionsSet` (Task 4); `Ctx`, `Out` (Task 7).
- Produces:
  - `Future<int> install(Ctx c, {Method? method})`
  - `Future<int> reinstall(Ctx c, {Method? method})`
  - `Future<int> uninstall(Ctx c)`
  - `void printStatus(Ctx c, GameFacts f, Method current)`

**Behavior:**
- All three exit 1 with `ADOFAI not found (looked in <path>).` when the game is missing.
- The current method is `AmmRecord.load(root).method ?? inferMethod(...)`.
- `install`:
  - **Loader present:** `printStatus`, then, if `method` was given and differs from the current one, print `To switch, run: amm reinstall --<method>`. Exit 0. No network.
  - **No loader:** call `resolveInstall(f, requested: method, fallback: c.config.defaultMethod)`.
    - A `Refuse` prints its message and exits 1.
    - A `Proceed` with `confirm` must pass `c.out.confirm`.
    - Then run `InstallScripts.install(method)` through `c.runScript`, routing lines to `c.out.log`/`subtitle`. A non-zero exit prints `Install failed.` and exits 1.
    - Then `_afterInstall`.
- `_afterInstall(c, f, method)`:
  - For `ml`: call `SteamConfig.setLaunchOptions(<game>/setup_helper.sh)`, reporting the outcome the way `AppState._applyLaunchOptions` does, in English.
  - Mod move. For `ml`: if `ModStore.findUmmMods(<game>/Mods)` is non-empty, ask `Move <n> UMM mod(s) from Mods/ to UMMMods/ so UMMBridge loads them?`. For UMM methods: if `<game>/UMMMods` has folders, ask `Move <n> mod(s) from UMMMods/ back to Mods/?`, and if `<game>/Mods` has `*.dll` files, say `MelonLoader mods in Mods/ won't load under UMM.`
  - On yes, call `ModStore.moveMods` and `record.movePaths`.
  - Save `record.method = method`.
- `uninstall`:
  - No loader prints `No mod loader installed.` and exits 0.
  - Otherwise confirm `Remove <MelonLoader|Unity Mod Manager> from <path>? Mods stay in place.`, run `InstallScripts.uninstall(current)`, and clear launch options for `ml`. Save `record.method = null`.
- `reinstall`:
  - No loader prints `No loader installed; installing.` and runs `install`.
  - **Target equals current** (`method ?? current`): confirm `Reinstall <loader> (<method>)? Mods stay in place.`, uninstall, install, `_afterInstall` (mods stay, so its move offer finds nothing new).
  - **Switch, rosetta to ml/native on Apple Silicon without the arm64 slice:** confirm, uninstall, then print `Verify game files in Steam to restore the arm64 slice: steam://validate/977950` and `Then run: amm install --<target>`. Exit 0.
  - **Any other switch:** run `resolveInstall` for the target *before* uninstalling anything (a refusal changes nothing). Confirm `Switch from <current> to <target>? This uninstalls <current>, installs <target>, then offers to move your mods.` plus any `Proceed.confirm` text. Then uninstall current, clear launch options if it was `ml`, install target, `_afterInstall`.
- `printStatus` lines:
  - `Game:`
  - `Version:`: the version, or `v<major> (exact version unknown)`, or `unknown`.
  - `Loader:`: `MelonLoader (ml)`, `Unity Mod Manager (<method>)` or `none`.
  - `Files:`: `complete` or `missing: a, b`.
  - `Launch options:` (ml only): `set`, `not set` or `Steam config not found`.
  - `arm64 slice:` (Apple Silicon only): `present` or `stripped`.

- [ ] **Step 1: Write the failing tests.** Use a temp game, a fake `facts`, a fake `runScript` that records each `ScriptCall` and returns 0 (or 1 where noted), and a `yes: true` ctx unless noted.
  - `install with loader present prints status and runs nothing`.
  - `install --rosetta on v3 needs confirmation`: a non-interactive Out without yes gives exit 1 and no script calls.
  - `install uses saved default`: config default `native`, v3, Apple Silicon, so the calls are `[umm.sh ['native']]`.
  - `install ml offers to move UMM mods and updates record paths`: `Mods/A/Info.json` ends up as `UMMMods/A`, and the record path `Mods/A` becomes `UMMMods/A`.
  - `failed script exits 1 and records nothing`.
  - `reinstall switching umm to ml runs uninstall then install`: the calls are `[umm-uninstall.sh ['native'], melonloader.sh []]`.
  - `reinstall refused target changes nothing`: v2 with `--ml` gives exit 1 and no calls.
  - `reinstall rosetta to ml with stripped slice stops after uninstall`: the calls are `[umm-uninstall.sh ['rosetta']]`, and the output contains `steam://validate/977950`.
  - `uninstall without loader exits 0`.
  - `uninstall clears record method`.
- [ ] **Step 2:** Run `(cd cli && dart test test/loader_commands_test.dart)`. Expected: FAIL.
- [ ] **Step 3:** Implement the above.
- [ ] **Step 4:** Run `(cd cli && dart test && dart analyze)`, then `dart run bin/amm.dart install` on the dev Mac. Expected: tests pass, and the real status prints with no network use (check with Wi-Fi off).
- [ ] **Step 5:** Commit with message `Add install, reinstall and uninstall to amm`.

### Task 9: CLI mod commands (`modinstall`/`mi`, `mr`, `upgrade`)

**Files:**
- Modify: `cli/lib/src/mod_commands.dart`, `cli/lib/src/cli.dart`
- Test: `cli/test/mod_commands_test.dart`

**Interfaces:**
- Consumes: `ModOps`, `ModTarget`, `InstallPlan`, `UpgradeScan` (Task 6); `Catalog` (Task 5); `AmmRecord`, `ModStore` (Task 4).
- Produces:
  - `Future<int> modinstall(Ctx c, List<String> slugs)`
  - `Future<int> remove(Ctx c, List<String> slugs, {bool keep = false})`
  - `Future<int> upgrade(Ctx c, List<String> slugs)`: an empty list means all.
  - `ModTarget targetFor(GameFacts f)`: `melon` is `f.loader == LoaderKind.melonLoader`, and `platform` is `f.os`.

**Behavior:**
- `modinstall`:
  - Needs the game and a loader; with no loader it prints `No mod loader installed. Run \`amm install\` first.` and exits 1.
  - Load the catalog and print its warnings. If `plan.missing` is non-empty, print `Unknown mod(s): a, b. Try \`amm search\`.` and exit 1 before installing anything.
  - Otherwise print `Installing: a, b (dependency), c`. For each entry, a progress line shows the percentage on a TTY and is replaced by `✓ <slug> <version>` or `✗ <slug>: <error>`. Record and save after each success.
  - Exit 1 if any failed.
- `remove`:
  - Needs the game. Confirm `Delete <n> mod(s): a, b?`, or `Archive <n> mod(s): a, b? You can restore them in the GUI.` with `--keep`.
  - Run `ModOps.remove` for each slug and report the removed paths. Save the record.
  - Exit 1 if any slug matched nothing; the others are still removed.
- `upgrade`:
  - Needs the game and a loader. Run `ModOps.upgrades`, filtered to `slugs` when given; a requested slug with no upgrade prints `<slug> is up to date.`
  - Print `Upgrading: a 1.0 → 1.1, …`, then run each `ModOps.upgrade` with the same progress lines, recording and saving.
  - Print `Skipped (unknown source): x, y` when `unknown` is non-empty.
  - Nothing to do prints `All mods are up to date.`

- [ ] **Step 1: Write the failing tests** in `mod_commands_test.dart`. Use a temp game with a MelonLoader folder, a fake catalog with MockClient zips, and yes ctx.
  - `mi installs dependencies first and records both`.
  - `mi with unknown slug installs nothing and exits 1`.
  - `mi without loader exits 1`.
  - `mr asks before deleting`: non-interactive without yes gives exit 1, and the files remain.
  - `mr --keep archives`.
  - `upgrade with one slug only touches that mod`.
  - `upgrade reports up to date`.
- [ ] **Step 2:** Run `(cd cli && dart test test/mod_commands_test.dart)`. Expected: FAIL.
- [ ] **Step 3:** Implement the above.
- [ ] **Step 4:** Run `(cd cli && dart test && dart analyze)`, then on the dev Mac (with a loader installed) `dart run bin/amm.dart mi xperfect`, `dart run bin/amm.dart -l` and `dart run bin/amm.dart mr xperfect -y`. Expected: it installs, is listed with source `mods.json`, and is removed.
- [ ] **Step 5:** Commit with message `Add modinstall, mr and upgrade to amm`.

### Task 10: TUI (`ammtui`)

**Files:**
- Create: `cli/lib/src/tui.dart`
- Modify: `cli/bin/amm.dart`, `cli/lib/src/cli.dart` (`tui` command)
- Test: `cli/test/tui_test.dart`

**Interfaces:**
- Consumes: every command function from Tasks 7–9 (`install`, `reinstall`, `uninstall`, `setDefault`, `list`, `search`, `modinstall`, `remove`, `upgrade`); `ModOps.upgrades` for the update count.
- Produces:
  - `Future<int> runTui(Ctx c)`
  - `enum MenuAction { install, reinstall, uninstall, setDefault, list, search, remove, upgrade, quit }`
  - `class MenuState { int selected; MenuAction? handle(String key); String render({required String header, required Map<MenuAction, String> notes}); }`
  - `class PickerState { PickerState(List<String> rows, {bool multi, Set<int> preselected}); int cursor; Set<int> chosen; bool? handle(String key); String render(String title); }`. `handle` returns true on enter (done), false on `q`/esc (cancel), and null otherwise.

**Behavior** (layout from the spec's mockup):
- Header: `ADOFAI Mod Manager` on the left; `v<version> · <MelonLoader|UMM|no loader> · default: <m>` on the right.
- Items and shortcuts: `Install loader i`, `Reinstall loader R`, `Uninstall loader U`, `Set default method d`, `List installed mods l`, `Search & install mods s`, `Remove mods r`, `Upgrade mods u`, `Quit q`.
- Footer: `↑↓ move · enter select · letter = shortcut`.
- Keys: up `\x1b[A`, down `\x1b[B`, enter `\r` or `\n`. Letter shortcuts are case-sensitive.
- The notes column shows `(<n> installed)` from the local scan right away, and `(<n> updates)` once a background `Catalog.load` finishes (then the menu redraws). If the catalog fails, there is no update note.
- Terminal: raw mode via `stdin.echoMode = false; stdin.lineMode = false`, then clear screen and hide the cursor. Restore modes and the cursor in `finally` and on `ProcessSignal.sigint`.
- Running an action:
  1. Restore line mode and clear the screen.
  2. Call the command function with a normal interactive ctx, so commands ask their own y/N questions and output scrolls normally *(plan's call: this is the spec's "scrolling pane")*.
  3. Show `Press any key to return.`, then return to raw mode.
- Install and reinstall first open a picker over `ml`, `native`, `rosetta` with the saved default preselected. On Linux it shows `ml` only.
- Set default uses the same picker.
- Search: the prompt `Search: ` (line mode) feeds a multi picker over results (`slug  version  name`, JALib rows suffixed `[broken]`); enter runs `modinstall(chosen)`.
- Remove: a multi picker over installed mods feeds `remove(chosen)`.
- Upgrade: a multi picker over upgrades, all preselected, feeds `upgrade(chosen)`.
- When `stdin.hasTerminal` is false, `runTui` prints `ammtui needs a terminal.` and returns 1.

- [ ] **Step 1: Write the failing tests** in `tui_test.dart`:
  - `shortcuts map case-sensitively`: `R` gives reinstall, `r` gives remove, `U` gives uninstall, `u` gives upgrade.
  - `down then enter selects second item`.
  - `selection wraps`.
  - `render marks the selected row with >`.
  - `render shows notes`.
  - `picker space toggles in multi mode`.
  - `picker enter returns true, q returns false`.
- [ ] **Step 2:** Run `(cd cli && dart test test/tui_test.dart)`. Expected: FAIL.
- [ ] **Step 3:** Implement `tui.dart`, then wire `amm tui` and the `ammtui` program-name check.
- [ ] **Step 4:** Run `(cd cli && dart test)`. Then `dart compile exe bin/amm.dart -o /tmp/ammbin/amm && ln -sf amm /tmp/ammbin/ammtui && /tmp/ammbin/ammtui`. Expected: tests pass and the menu opens.
  - **If the symlink opens the CLI usage instead** (`Platform.executable` resolved the link), keep the `amm tui` route. Task 11's installer then writes `ammtui` as a two-line wrapper (`#!/bin/sh` / `exec "$(dirname "$0")/amm" tui "$@"`) instead of a symlink. Note that in the commit message.
  - Also check that Ctrl+C inside the menu restores the terminal (typing echoes again).
- [ ] **Step 5:** Commit with message `Add ammtui`.

### Task 11: Release builds, install script, README

**Files:**
- Modify: `.github/workflows/release-gui.yml` (add job `cli`)
- Create: `cli/install.sh`
- Modify: `README.md`, `README.kr.md`
- Test: `.github/scripts/test_scripts.sh` (add `bash -n cli/install.sh` and an asset-name check)

**Interfaces:**
- Consumes: `cli/bin/amm.dart`. Also Task 10's outcome: whether `ammtui` is a symlink or a wrapper.
- Produces: release assets `amm-darwin-arm64`, `amm-darwin-x64`, `amm-linux-x64`, and the installer at `https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/cli/install.sh`.

**Workflow job `cli`** (same triggers as the GUI job: tags `v2.*` and `workflow_dispatch`):
- Matrix: `{os: macos-latest, target: darwin-arm64}`, `{os: macos-15-intel, target: darwin-x64}`, `{os: ubuntu-latest, target: linux-x64}`.
- Steps:
  1. Checkout and `dart-lang/setup-dart@v1`.
  2. `dart pub get && dart test` in `core/` and `cli/`.
  3. `dart compile exe bin/amm.dart -o amm-${{ matrix.target }}` in `cli/`.
  4. Attach `cli/amm-*` with `softprops/action-gh-release@v2`, only when `startsWith(github.ref, 'refs/tags/')`.

**`cli/install.sh`:**
- Starts with `set -euo pipefail`.
- OS from `uname -s`: `Darwin` gives `darwin`, `Linux` gives `linux`, anything else gives `error: amm supports macOS and Linux only.` and exit 1.
- Arch:
  - macOS: `sysctl -n hw.optional.arm64` = `1` gives `arm64`, else `x64`.
  - Linux: `uname -m` = `x86_64` gives `x64`; anything else gives `error: amm on Linux is x64 only for now.`
- Download `https://github.com/sbrothers7/UMMInstall/releases/latest/download/amm-$os-$arch` with `curl -fL` to a `mktemp` file, `chmod +x` it, and `mv` it to `${AMM_INSTALL_DIR:-$HOME/.local/bin}/amm`, after `mkdir -p` (no sudo).
- Create `ammtui` next to it, as a symlink or wrapper per Task 10.
- Print `Installed amm to <dir>`. If `<dir>` isn't on `PATH`, also print `Add this to your shell profile: export PATH="<dir>:$PATH"`.
- Rerunning overwrites, so it updates.

**README** (`README.md` and `README.kr.md`): a "Command line (amm)" section with:
- the curl line from the spec;
- a table of the commands (the spec's Commands table, condensed to one line each);
- a note that `ammtui` opens the menu;
- a note that Linux is MelonLoader-only on the native build.

In the Korean README, translate the prose and keep commands verbatim.

- [ ] **Step 1: Write the failing check.** Extend `test_scripts.sh`:
  - `bash -n cli/install.sh`;
  - assert that every `-o amm-` target in `release-gui.yml` matches `^amm-(darwin-arm64|darwin-x64|linux-x64)$` (with `grep -o 'target: [a-z0-9-]*'`), and that none end in `.zip`;
  - run `AMM_INSTALL_DIR=$(mktemp -d) bash cli/install.sh` with a stub `curl` on `PATH` that writes `#!/bin/sh\necho stub` to its `-o` file, then assert that `$DIR/amm` is executable and `$DIR/ammtui` exists.
- [ ] **Step 2:** Run `bash .github/scripts/test_scripts.sh`. Expected: FAIL (no `cli/install.sh`).
- [ ] **Step 3:** Implement the workflow job, `install.sh` and the README sections.
- [ ] **Step 4:** Run `bash .github/scripts/test_scripts.sh`. Expected: `scripts ok`. After the owner OKs a push, run `gh workflow run release-gui.yml --ref amm-cli` and confirm all four jobs (GUI plus three CLI) pass. Nothing is attached, since this isn't a tag run.
- [ ] **Step 5:** Commit with message `Build amm binaries on release and add the curl installer`. The tag and release itself stay with the owner.
