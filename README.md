# macOS ADOFAI Mod Installer

English | [한국어](README.kr.md)

A native macOS installer for [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM) or [MelonLoader](https://melonwiki.xyz/) (recommended on v3.x+) on [A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/). Handles both the legacy Unity 2022 build (v2.x) and the current Unity 6 build (v3.x+), and bundles a mod select/installer.

> [!Note]
> Currently, any mods that depend on JALib (JipperResourcePack, PACL, BetterCalibration, etc.) are not working. This will be fixed soon.

## Auto-installer Download

https://github.com/sbrothers7/UMMInstall/releases/latest

## Command line (amm)

```
curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/cli/install.sh | bash
```

| Command | What it does |
|---|---|
| `amm install` | Install the default loader (or show what is installed) |
| `amm install --ml` / `--native` / `--rosetta` | Install MelonLoader / UMM native / UMM Rosetta |
| `amm reinstall` | Reinstall the current loader |
| `amm reinstall --<method>` | Reinstall with another method |
| `amm uninstall` | Remove the loader |
| `amm default [method]` | Show or set the default loader |
| `amm status` | Show the game, loader and mod counts |
| `amm list` / `-l` | List installed mods |
| `amm search [text]` / `-s` | Search the mod list (no text lists every mod with its versions and game versions) |
| `amm modinstall <mod>` / `mi` | Install a mod |
| `amm mr <mod>` (`--keep`) | Remove a mod (`--keep` keeps its settings) |
| `amm upgrade` | Upgrade all installed mods |
| `amm upgrade <slug>` | Upgrade one mod |
| `amm update` | Update amm, ammtui and the GUI app (in Applications) to the latest release |

`ammtui` opens the interactive menu. Add `-y` to skip confirmations. On Linux (x64), only the native build with MelonLoader is supported.


## Requirements

- macOS 13+
- A Steam install of ADOFAI at the default path (`~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice`)

The installer auto-installs [Homebrew](https://brew.sh) (if needed) and any of `git`, `dotnet`, `mono`, `expect`, `wget` it needs. You may be prompted for your password during the Homebrew install.

[More Info](INFO.md)
