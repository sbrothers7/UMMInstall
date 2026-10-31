# amm: CLI and TUI for the ADOFAI mod installer

Status: design, not started. Date: 2026-10-31.

Marking: **decided** = the owner chose it. *(designer's call)* = chosen while
writing this doc; the owner can override it. Anything not marked is fact about
the current code or the services it uses.

## Why

The Flutter GUI (`gui/`) is bulky and slow for terminal users. The owner wants
the same installer as a command-line tool (`amm`) and a full-screen terminal UI
(`ammtui`). Competing tools (KGH1113/ADOFAIModManager, modlist.org's own app)
are GUI-only, so a real CLI is also something they don't have.

## Goals

- `amm` does everything the GUI does for installing loaders and mods, with
  commands a terminal user can script.
- `ammtui` puts the same actions behind a keyboard-driven menu.
- One code path for game detection, loader install, and mod install, shared by
  the GUI, CLI, and TUI, so a fix lands in all three.
- Installs with one `curl … | bash` line on macOS and Linux.

## Non-goals

- **Windows (decided).** No Windows test machine. Windows users already have
  better tools; the existing PowerShell scripts in `windows/` stay as they are.
- Making the loader install dependency-free (no Homebrew/mono/dotnet). That is a
  separate project. `amm` runs the same `macos/*.sh` scripts the GUI runs today.
- Fixing JALib-dependent mods. Separate project.
- Proton on Linux (decided: native Linux build only for now).
- Rewriting the GUI. It changes only as much as moving shared logic requires.

## Anti-goals (would be a failure even if it works)

- A CLI that feels slow: local commands (`list`, `default`, status) must print
  without network calls and start instantly (native binary, no VM warm-up).
- Breaking existing users: the GUI's self-updater, old v1 (Swift) apps, and the
  `mods.json` they all read must keep working. See "Release" for the trap.
- Silently changing the game install: every command that modifies files says
  what it will change; destructive ones (`uninstall`, `reinstall`, `mr`) confirm
  unless `-y` is passed *(designer's call for `-y`)*.

## Commands (decided unless marked)

| Command | Alias | Does |
|---|---|---|
| `amm install` | | Detect game + version + loader state. If no loader: install with the saved default method. If a loader is present: print its status and stop. |
| `amm install --ml` / `--native` / `--rosetta` | | Same, but use this method for this run instead of the default. |
| `amm reinstall` | | Uninstall then install with the same method. Mods are left in place *(designer's call)*. |
| `amm reinstall --ml` / `--native` / `--rosetta` | | If that's a different method from the installed one: switch loaders and move mods (see "Switching loaders"). Same method: plain reinstall. |
| `amm uninstall` | | Remove the loader. Mods are left in place *(designer's call)*. |
| `amm default ml\|native\|rosetta` | | Save the default method. Starts as `ml`. |
| `amm list` | `-l` | List installed mods in `Mods/` and `UMMMods/`, with version and source when known. |
| `amm search <query>` | `-s` | Search modlist.org plus our `mods.json`. |
| `amm modinstall <slug>…` | `mi` | Install one or more mods by slug, plus their dependencies. |
| `amm mr <slug>…` | | Remove mods. Deletes by default; `--keep` archives instead, like the GUI's "Keep Data" *(designer's call)*. |
| `amm upgrade` | | Update every mod amm can match to a newer version. |
| `amm upgrade <slug>` | | Update one mod. |
| `ammtui` | | Full-screen menu (see TUI). |

Both the word form and the flag form are accepted for `list` and `search`
(decided).

Status output for `amm install` when a loader exists *(designer's call for the
exact fields)*: game path, game version, loader (MelonLoader / UMM / none),
whether loader files are complete, whether Steam launch options are set (MelonLoader
on macOS/Linux), and on Apple Silicon whether the game binary still has its
arm64 slice.

### Install methods

Today `macos/adofai-umm.sh` chooses its path purely from the game's major
version: v2 → UMM via `Console.exe` under mono, then strips the arm64 slice
(this is what "rosetta" means); v3 → UMM via kkorenn's `MacTuiInstaller`,
arm64 native (this is "native"). `macos/adofai-melonloader.sh` is "ml".

- **macOS, game v2: rosetta is forced (decided).** `--ml` / `--native` on v2
  stop with a one-line note that those paths are untested there. The saved
  default is ignored on v2. (Background: MelonLoader + UMMCompat loaded
  Sapphire and Bismuth on v2, but UMM's Ctrl+F10 menu didn't work, so it can't
  be promised.)
- **macOS, game v3: `ml` (default), `native`, and `rosetta` are all offered
  (decided).** `rosetta` on v3 means forcing the v2 path (Console.exe under
  mono + arm64 strip) on a v3 game, which has never been tried.
  *(designer's call)* Before running it, `amm` says it's untested on v3 and
  that the strip means verifying game files in Steam before `ml`/`native`
  work again, then asks to confirm (`-y` skips).
- **Linux, native build: `ml` only** *(designer's call)*. `native` and
  `rosetta` are macOS install paths and are refused there. See "Linux".

- *(designer's call)* Intel Macs: `native` on v3 is refused, because
  `adofai-umm.sh` builds MacTuiInstaller for `osx-arm64` only. `ml` works
  (the MelonLoader script picks the x64 build). On Intel, "rosetta" is plain
  x86_64 UMM via Console.exe; the script already skips the strip there.
- *(designer's call)* When the arm64 slice is missing and the chosen method
  needs it (`ml`/`native` on Apple Silicon), stop and print the fix: verify
  game files in Steam (`steam://validate/977950`), as the GUI's NeedsVerify
  screen does.

The CLI passes the chosen method to the scripts; it does not reimplement them.
*(designer's call)* Scripts get an optional method argument; with no argument
they must behave exactly as today, because released GUIs download
`macos/*.sh` live from the `v2` branch (`install_scripts.dart:8`) and pick up
any change the moment it's pushed. The method used is recorded in
`.amm/installed.json` so `uninstall`/`reinstall` run the matching removal;
with no record, infer it (MelonLoader folder → `ml`; UMM on v2 → `rosetta`;
UMM on v3 with the arm64 slice stripped → `rosetta`; other UMM on v3 →
`native`).

### Switching loaders (decided: `reinstall --<method>` switches)

When `amm reinstall --<method>` names a different method from the installed
one: uninstall the current loader, install the new one, then move mods to where
the new loader reads them, asking before moving — the GUI's migrate flow
(`AppState.startMigration` / `moveMigratableMods` in `app_state.dart`),
extended to every pair:

- UMM (`native`/`rosetta`) → `ml`: move UMM mod folders (folders with an
  `Info.json`) from `Mods/` to `UMMMods/`; set Steam launch options. This is
  exactly what the GUI does today.
- `ml` → UMM: move `UMMMods/*` back to `Mods/`; clear launch options
  *(designer's call; the GUI has no reverse flow)*. MelonLoader-native mods in
  `Mods/` (loose `.dll`s) stay and simply stop loading; say so.
- `rosetta` → `native` or `ml` on Apple Silicon: mods stay. The arm64 slice
  has to come back first, so stop after uninstalling and tell the user to
  verify game files in Steam, then rerun *(designer's call)*.
- `native` → `rosetta`: mods stay; same untested-on-v3 confirmation as install.

Paths in `.amm/installed.json` are updated for moved mods. `amm install
--<method>` with a different loader already present prints status and points
at `amm reinstall --<method>`; it never switches on its own *(designer's
call)*.
Scripts already speak a line protocol (`info:`/`ok:`/`error:`/`detail:`/
`subtitle:` prefixes) parsed by `gui/lib/src/install/script_runner.dart`. The
CLI prints those lines (colored by level when stdout is a TTY) instead of
feeding a GUI log.

## Where mods come from

Two sources, merged:

1. **Our `mods.json`** (repo root, fetched from `main` at runtime). Kept current
   by the daily bot in `.github/workflows/mods.yml` (already built). The owner
   wants JRP and the other mods not on modlist.org kept here (decided).
2. **modlist.org** public API (no auth):
   - `GET https://modlist.org/api/mods?game=adofai&search=<q>&page=&limit=` →
     `{mods, pagination}`. 18 mods as of 2026-10-31.
   - `GET /api/mods/<slug>` → one mod.
   - `GET /api/mods/<slug>/download?loader=melonloader|umm&platform=macos|linux&gameVersion=<v>`
     → redirects to the file.
   - Each mod's `latestVersion.files[]` says which `loader`, `platform`, and
     `gameVersion` range each file is for; `dependencies` lists other mods by
     slug.

*(designer's call)* Each `mods.json` entry gets a `slug` field. Use the
modlist.org slug when the mod is listed there (e.g. `quartz`, `sapphire`,
`enhancedeffectremover`), otherwise a short lowercase name (`jrp`,
`tufhelper`, `adofaitweaks`, …). When both sources have a slug, **our entry
wins**, because it carries the v2 / MelonLoader download overrides. Adding `slug` means adding it to
`STR_FIELDS` in `.github/scripts/update_mods.py`, which rejects unknown fields.

`mods.json` already supplies `version` (and `versionMelon`) for every entry the
bot tracks; entries it can't track have no version and are never offered as
upgrades.

Filtering is the same as the GUI's `visibleMods`: hide entries with `v2:false`
on v2 / `v3:false` on v3. JALib mods (`jalib: true`) show in search marked as
broken, and `mi` refuses them until the JALib project lands *(designer's call)*.

## Remembering what amm installed *(designer's call)*

`mi` writes a record so `upgrade` and `mr` know what they're dealing with:
`<game folder>/.amm/installed.json`, one entry per slug with source
(`mods.json` / `modlist.org`), version, and the files/folders it created. It
lives in the game folder so it follows the install and is shared by the GUI, CLI,
and TUI once they share the core.

Mods installed some other way (GUI before this change, by hand): `list` shows
them; `upgrade` tries to match by the `Id` in their `Info.json` against known
mods and otherwise skips them with a note; `mr` works on them by folder name.

## Shared core *(designer's call)*

Only `gui/lib/src/app_state.dart` imports Flutter (`ChangeNotifier`). Everything
it calls is plain Dart: `platform/game_paths.dart`, `platform/steam_config.dart`,
`install/script_runner.dart`, `install/mod_downloader.dart`,
`install/install_scripts.dart`, `mod_registry.dart`, `updater.dart`,
`models.dart`.

Plan: a plain Dart package (no Flutter) holding that code plus the logic now
inside `AppState` (install/uninstall/migrate flows, scan/archive/restore/delete
mods, launch-option handling). The GUI depends on it by path and keeps
`AppState` as a thin `ChangeNotifier` wrapper. The CLI is a second package with
`bin/amm.dart`, compiled with `dart compile exe`.

The GUI must behave the same after the move. Its localized messages (`t(en, ko)`)
stay in the GUI; the core reports events/results, and each front end words
them.

### Install rules the core must keep

Both were fixed in the GUI's `mod_downloader.dart` on 2026-10-31 (covered by
`gui/test/mod_downloader_test.dart`); moving the code must not lose them.

- **Zip path safety.** Entries that resolve outside the extraction folder
  (`../x`) are rejected and symlink entries skipped. modlist.org files are
  uploaded by third parties, so this matters more once they're installable.
- **Game-root-layout zips.** If a zip's top level contains `Mods/`,
  `UserLibs/`, `Plugins/`, or `UserData/` (e.g. `EnhancedEffectRemover_ML.zip`,
  Quartz's MelonLoader build), those folders merge into the game root.
  Otherwise: single folder → mods folder; loose files → `<mods folder>/<id>/`.
  (This replaced the Quartz-only special case, so `install: "quartz"` is no
  longer needed by the v2 GUI; old v1 apps still read it.)

## TUI (decided: a menu of the main CLI actions)

```
 ADOFAI Mod Manager                        v3.0.2 · MelonLoader · default: ml
 ──────────────────────────────────────────────────────────────────────────
  > Install loader          i
    Reinstall loader        R
    Uninstall loader        U
    Set default method      d
    List installed mods     l     (6 installed)
    Search & install mods   s
    Remove mods             r
    Upgrade mods            u     (2 updates)
    Quit                    q
 ──────────────────────────────────────────────────────────────────────────
  ↑↓ move · enter select · letter = shortcut
```

*(designer's calls)*: header shows game version, active loader, saved default.
Each item opens its own screen; search shows a result list where you toggle
mods and press enter to install; remove/upgrade use the same list. Uppercase
shortcuts for destructive actions. Script output streams into a scrolling pane.
`ammtui` is the same binary as `amm`, started under that name (symlink), so
there's one thing to build and ship.

## Distribution (decided: curl script in the README)

```bash
curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/cli/install.sh | bash
```

*(designer's calls)*: the script detects OS (macOS/Linux) and CPU
(arm64/x64), downloads the matching binary from the latest GitHub release into
`~/.local/bin/amm`, symlinks `ammtui` next to it, needs no sudo, and prints the
PATH line to add if `~/.local/bin` isn't on PATH. Rerunning it updates.
No `amm self-update` (would clash with `upgrade` meaning mods). Config lives at
`$XDG_CONFIG_HOME/amm/config.json`, default `~/.config/amm/config.json`
(holds the default method).

### Release (constraint)

- **CLI binaries must not be `.zip`.** The GUI's updater takes the first `.zip`
  whose name contains `mac`/`macos`/`darwin`/`osx`
  (`gui/lib/src/updater.dart:46`), and the old v1 Swift updater takes the first
  `.zip` of any name. Ship bare binaries: `amm-darwin-arm64`, `amm-darwin-x64`,
  `amm-linux-x64`.
- **CLI ships on the same GitHub releases as the GUI**, same version. The
  install script and both updaters all read "latest release"; a separate CLI
  release with no GUI zip would become "latest" and break the GUI and v1 update
  checks.
- Build in `.github/workflows/release-gui.yml` (or a sibling triggered by the
  same tags). `dart compile exe` can't cross-compile to macOS, so each target
  needs a runner of that OS/arch.

## Linux (decided: native Linux build, loader install included)

Proton (the Windows build under Wine) is out of scope for now.

Already there:
- `game_paths.dart` finds the game across normal, Debian, and Flatpak Steam
  roots via `libraryfolders.vdf`, and detects UMM under
  `A Dance of Fire and Ice_Data/Managed`.
- `steam_config.dart` already knows Linux Steam roots for editing launch
  options in `localconfig.vdf`.

To build:
- `linux/adofai-melonloader.sh` and `linux/adofai-melonloader-uninstall.sh`,
  speaking the same line protocol as the macOS scripts. The MelonLoader fork
  the macOS script uses (kkorenn/MelonLoader v0.7.3) ships
  `MelonLoader.Linux.x64.zip`. Install UMMBridge (`ummcompat`) and set Steam
  launch options as on macOS.
- Game version detection on Linux (`detectGameVersion` returns null off macOS
  today); only v2 vs v3 matters.
- `install_scripts.dart` returns the Linux script URLs. The GUI gets them too,
  though no Linux GUI build is released (CI is macOS-only).

*(designer's call)* Linux is x64 only: the fork has no Linux arm64 MelonLoader
build, so `amm-linux-arm64` is dropped from the release list.

## Left to the builder

- TUI library (must be pure Dart and build with `dart compile exe`) and CLI
  argument parsing (`package:args` is the obvious choice).
- Package layout and names inside the repo.
- How version detection works on Linux (e.g. reading Unity version data from
  the game's `_Data` folder) — only v2 vs v3 matters.
- Output formatting details; a `--json` flag if cheap.
- Test approach, keeping to the repo's habit of small runnable checks.

## Decisions from review (2026-10-31)

A builder read an earlier draft; the owner answered the three questions only
they could:

1. Linux gets loader install, for the native Linux build only (not Proton).
2. `--rosetta` is offered on v3 Macs.
3. `amm reinstall --<method>` switches loaders and moves mods, like the GUI's
   migrate flow.
