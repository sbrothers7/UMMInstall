# More Info

## Shell

```bash
./adofai-umm.sh             # install
./adofai-umm-uninstall.sh   # uninstall
```

After install, launch the game via Steam and press **Ctrl+F10** for the UMM menu.

## Build from Source (Swift GUI Application)

Build the SwiftUI app:

```bash
cd swift
./build.sh                              # host arch; requires Swift CLI tools
./build.sh --version 1.0.10              # set bundle version (matches GitHub release tag)
./build.sh --version 1.0.10 --zip        # also produce a distributable .zip
UNIVERSAL=1 ./build.sh --version 1.0.10  # universal arm64+x86_64 (requires full Xcode)
```

## Version-specific Notes

- **v2.x (Unity 2022):** patches `UnityEngine.CoreModule.dll` via UMM's `Console.exe` under Mono, then on Apple Silicon strips the arm64 slice so the game runs under Rosetta (UMM's runtime is x86_64-only on this build). To fully restore the arm64 slice after uninstall, verify game files via Steam → Properties → Installed Files.

- **v3.x+ (Unity 6):** uses [kkorenn/unity-mod-manager](https://github.com/kkorenn/unity-mod-manager)'s `MacTuiInstaller`, which is built once and cached at `~/.cache/adofai-umm-installer/`. On Apple Silicon, make sure Steam is **not** set to "Open using Rosetta" (Steam.app → Get Info) — the native installer fails if Steam runs under Rosetta.

## GUI Features

- **Auto-update on launch:** The app checks GitHub Releases on every launch and self-replaces if a newer version is available (no manual download required).

- **In-app Homebrew install:** If Homebrew is missing, a single native macOS auth dialog appears; the installer runs as the user (via a temporary sudoers entry) and streams its output into the same progress log used for UMM. No Terminal popup or app relaunch needed.

- **MelonLoader support:** On v3.x+ you can install [MelonLoader](https://melonwiki.xyz/) (recommended) instead of UMM — it auto-installs the UMMCompat plugin (square3ang), sets the Steam launch options for you, and routes mods into `UMMMods/`. If UMM is already installed, the app offers to migrate (uninstall UMM, install MelonLoader, and move existing UMM mods to `UMMMods/`). Mods that ship a dedicated MelonLoader build (e.g. Quartz) use it automatically when MelonLoader is the active loader.

- **Bundled mod picker:** Selects compatible releases per game version automatically; mods without a v3-compatible release are hidden on v3.x+, and mods that dropped v2 support fall back to pinned older builds on v2.x.

## Updating the Mod List

The mod picker is driven by [mods.json](mods.json), fetched from this repo at launch — edit and push it to change the available mods **without rebuilding the app**. Each entry:

- `id` — display name.
- `url` — default download.
- `urlV2` (optional) — download used on the v2.x build.
- `urlMelon` (optional) — download used when the active loader is MelonLoader.
- `v2` / `v3` (default `true`) — availability per game build.
- `jalib` (default `false`) — hidden behind a banner while JALib-dependent mods are broken.
- `install` (optional) — special install handler key (e.g. `quartz`, which places the plugin DLL and data folder for both the MelonLoader and UMM builds).
