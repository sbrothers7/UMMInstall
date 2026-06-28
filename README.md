# macOS ADOFAI Mod Installer

A native macOS installer for [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM) on [A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/). Handles both the legacy Unity 2022 build (v2.x) and the current Unity 6 build (v3.x+), and bundles a mod select/installer.

[A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/)용 [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM)의 네이티브 macOS 설치기입니다. 레거시 Unity 2022 빌드 (v2.x)와 현재 Unity 6 빌드 (v3.x+) 모두를 지원하며, 모드 선택 메뉴를 포함합니다.

> [!Note]
> Currently, any mods that depend on JALib (JipperResourcePack, PACL, BetterCalibration, etc.) are not working. This will be fixed soon.
> 
> 현재 JALib을 필요로 하는 모드 (지퍼 리소스펙, PACL, BetterCalibration, 등)는 v3에서 사용이 불가합니다. 빠른 시일 내에 고쳐질 예정입니다.

## Auto-installer Download | 자동설치기 다운로드

https://github.com/sbrothers7/UMMInstall/releases/latest

## Requirements | 요구 사항

- macOS 13+
- A Steam install of ADOFAI at the default path (`~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice`)
- 기본 경로(`~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice`)에 설치된 Steam 버전 ADOFAI

The installer auto-installs [Homebrew](https://brew.sh) (if missing) and any of `git`, `dotnet`, `mono`, `expect`, `wget` it needs. You may be prompted for your password during the Homebrew install.

설치기는 필요할 경우 [Homebrew](https://brew.sh)와 `git`, `dotnet`, `mono`, `expect`, `wget`을 자동으로 설치합니다. Homebrew 설치 중 비밀번호를 묻는 메시지가 표시될 수 있습니다.

### Shell | 터미널

```bash
./adofai-umm.sh             # install | 설치
./adofai-umm-uninstall.sh   # uninstall | 제거
```

After install, launch the game via Steam and press **Ctrl+F10** for the UMM menu.

설치 후, Steam을 통해 게임을 실행하고 UMM 메뉴를 열려면 **Ctrl+F10**을 누르세요.

### Build from Source (Swift GUI Application) | 소스에서 빌드 (Swift GUI 애플리케이션)

Build the SwiftUI app:

SwiftUI 앱을 빌드합니다:

```bash
cd swift
./build.sh                              # host arch; requires Swift CLI tools | 호스트 아키텍처; Swift CLI 도구 필요
./build.sh --version 1.0.1              # set bundle version (matches GitHub release tag) | 번들 버전 설정 (GitHub 릴리스 태그와 일치)
./build.sh --version 1.0.1 --zip        # also produce a distributable .zip | 배포용 .zip도 생성
UNIVERSAL=1 ./build.sh --version 1.0.1  # universal arm64+x86_64 (requires full Xcode) | 유니버설 arm64+x86_64 (전체 Xcode 필요)
```

## Version-specific Notes | 버전별 참고 사항

- **v2.x (Unity 2022):** patches `UnityEngine.CoreModule.dll` via UMM's `Console.exe` under Mono, then on Apple Silicon strips the arm64 slice so the game runs under Rosetta (UMM's runtime is x86_64-only on this build). To fully restore the arm64 slice after uninstall, verify game files via Steam → Properties → Installed Files.
- **v2.x (Unity 2022):** Mono에서 UMM의 `Console.exe`를 통해 `UnityEngine.CoreModule.dll`을 패치하며, Apple Silicon에서는 게임 바이너리의 arm64 슬라이스를 제거하여 Rosetta에서 실행되도록 합니다 (이 빌드의 UMM 런타임은 x86_64 전용). 제거 후 arm64 슬라이스를 완전히 복원하려면 Steam → 속성 → 설치 파일에서 게임 파일 무결성을 검증하세요.

- **v3.x+ (Unity 6):** uses [kkorenn/unity-mod-manager](https://github.com/kkorenn/unity-mod-manager)'s `MacTuiInstaller`, which is built once and cached at `~/.cache/adofai-umm-installer/`. On Apple Silicon, make sure Steam is **not** set to "Open using Rosetta" (Steam.app → Get Info) — the native installer fails if Steam runs under Rosetta.
- **v3.x+ (Unity 6):** [kkorenn/unity-mod-manager](https://github.com/kkorenn/unity-mod-manager)의 `MacTuiInstaller`를 사용하며, 한 번만 빌드되어 `~/.cache/adofai-umm-installer/`에 캐시됩니다. Apple Silicon에서는 Steam.app이 "Rosetta를 사용하여 열기"로 설정되어 있지 않은지 확인하세요 (Steam.app → 정보 가져오기) — Steam이 Rosetta로 실행되면 네이티브 설치 프로그램이 실패합니다.

## GUI Features | GUI 기능

- **Auto-update on launch.** The app checks GitHub Releases on every launch and self-replaces if a newer version is available (no manual download required).
- **실행 시 자동 업데이트.** 앱은 실행할 때마다 GitHub 릴리스를 확인하고, 새 버전이 있으면 자체적으로 교체합니다 (수동 다운로드 불필요).

- **In-app Homebrew install.** If Homebrew is missing, a single native macOS auth dialog appears; the installer runs as the user (via a temporary sudoers entry) and streams its output into the same progress log used for UMM. No Terminal popup or app relaunch needed.
- **앱 내 Homebrew 설치.** Homebrew가 없는 경우 macOS 네이티브 인증 대화상자가 한 번만 표시됩니다. 설치 프로그램은 사용자 권한으로 실행되어 (임시 sudoers 엔트리 사용) 출력이 UMM과 동일한 진행 로그에 표시됩니다. 터미널 팝업이나 앱 재실행이 필요하지 않습니다.

- **MelonLoader detection.** If [MelonLoader](https://melonwiki.xyz/) is installed (`MelonLoader.Bootstrap.dylib` at the game root), the app skips installing UMM and routes mods into `UMMMods/` instead of `Mods/` — designed for use with the UMMCompat plugin.
- **MelonLoader 감지.** [MelonLoader](https://melonwiki.xyz/)가 설치되어 있으면 (게임 루트에 `MelonLoader.Bootstrap.dylib`) UMM 설치를 건너뛰고 모드를 `Mods/` 대신 `UMMMods/`에 설치합니다 — UMMCompat 플러그인과 함께 사용하도록 설계되었습니다.

- **Bundled mod picker.** Selects compatible releases per game version automatically; mods without a v3-compatible release are hidden on v3.x+, and mods that dropped v2 support fall back to pinned older builds on v2.x.
- **내장 모드 선택기.** 게임 버전에 맞는 호환 릴리스를 자동으로 선택합니다. v3 호환 릴리스가 없는 모드는 v3.x+에서 숨겨지며, v2 지원이 중단된 모드는 v2.x에서 고정된 이전 빌드로 폴백됩니다.

## Updating the Mod List | 모드 목록 업데이트

The mod picker is driven by [mods.json](mods.json), fetched from this repo at launch — edit and push it to change the available mods **without rebuilding the app**. Each entry: `id`, `url`, optional `urlV2` (v2.x download), and flags `v2`/`v3` (default `true`; availability per game build) and `jalib` (default `false`; hidden with a banner while JALib-dependent mods are broken).

모드 선택기는 실행 시 이 저장소에서 가져오는 [mods.json](mods.json)으로 동작합니다 — 파일을 수정하고 푸시하면 **앱을 다시 빌드하지 않고** 모드 목록을 변경할 수 있습니다. 각 항목: `id`, `url`, 선택적 `urlV2` (v2.x 다운로드), 그리고 플래그 `v2`/`v3` (기본값 `true`; 게임 빌드별 제공 여부)와 `jalib` (기본값 `false`; JALib 의존 모드가 작동하지 않는 동안 배너와 함께 숨김).
