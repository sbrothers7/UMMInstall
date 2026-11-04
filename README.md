# macOS ADOFAI Mod Installer

English | [한국어](README.kr.md)

A native macOS installer for [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM) or [MelonLoader](https://melonwiki.xyz/) (recommended on v3.x+) on [A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/). Handles both the legacy Unity 2022 build (v2.x) and the current Unity 6 build (v3.x+), and bundles a mod select/installer.

> [!Note]
> Mods that depend on JALib (JipperResourcePack, PACL, BetterCalibration, etc.) are supported with MelonLoader on macOS, including Apple Silicon.

## Auto-installer Download

https://github.com/sbrothers7/UMMInstall/releases/latest

- macOS: `Installer-macos.zip`
- Linux (x64): `Installer-linux.tar.gz`. Unpack it anywhere and run `adofai-mod-installer/adofai_mod_installer`; the first launch adds it to your app menu. Needs GTK 3, which most desktops include.

## Command line (amm)

```
curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/cli/install.sh | bash
```

To remove amm (add `-s -- --keep-config` after `bash` to keep its settings; mod loaders, mods and the GUI app stay):

```
curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/cli/uninstall.sh | bash
```

| Command | What it does |
|---|---|
| `amm install` | Install the default loader (or show what is installed) |
| `amm install --ml` / `--native` / `--rosetta` | Install MelonLoader / UMM native / UMM Rosetta |
| `amm install --umm` | Install UMM with the classic patch (the same as `--rosetta`; Rosetta only on an Apple Silicon Mac) |
| `amm reinstall` | Reinstall the current loader |
| `amm reinstall --<method>` | Reinstall with another method |
| `amm uninstall` | Remove the loader |
| `amm default [method]` | Show or set the default loader |
| `amm status` | Show the game, loader and mod counts |
| `amm list` / `-l` | List installed mods |
| `amm search [text]` / `-s` | Search the mod list (no text lists every mod with its versions and game versions) |
| `amm install --mod <mod>` / `mi` | Install a mod |
| `amm mr <mod>` (`--keep`) | Remove a mod (`--keep` keeps its settings) |
| `amm upgrade` | Upgrade all installed mods |
| `amm upgrade <slug>` | Upgrade one mod |
| `amm update` | Update the CLI, TUI and GUI app (in Applications, or on Linux the copy in your app menu) to the latest release |
| `amm auto-update [on\|off]` | Show or set automatic updates (on by default: amm checks once a day before a command) |

`ammtui` opens the interactive menu (press `c` there to check for updates). Add `-y` to skip confirmations. On Linux (x64), the native build supports MelonLoader (recommended) or UMM (`--umm`), which needs `mono` and `expect` (e.g. `sudo apt install mono-complete expect`).


## Requirements

- macOS 13+
- A Steam install of ADOFAI at the default path (`~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice`)

The installer auto-installs [Homebrew](https://brew.sh) (if needed) and any of `git`, `dotnet`, `mono`, `expect`, `wget` it needs. You may be prompted for your password during the Homebrew install.

[More Info](INFO.md)
