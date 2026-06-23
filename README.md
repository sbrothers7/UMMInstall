# macOS ADOFAI Mod Installer

A native macOS installer for [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM) on [A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/). Handles both the legacy Unity 2022 build (v2.x) and the current Unity 6 build (v3.x+), and bundles a mod select/installer.

[A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/)용 [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM)의 네이티브 macOS 설치기입니다. 레거시 Unity 2022 빌드 (v2.x)와 현재 Unity 6 빌드 (v3.x+) 모두를 지원하며, 모드 선택 메뉴를 포함합니다.

> [!Note]
> Currently, due to kkorenn/unity-mod-manager injecting mod assemblies early, any jongyeol mods (JipperResourcePack, PACL, BetterCalibration, etc.) are not working. This will be fixed soon.
> 
> 현재 kkorenn/unity-mod-manager상 문제로 jongyeol님 모드 (지퍼 리소스펙, PACL, BetterCalibration, 등)는 v3에서 사용이 불가합니다. 빠른 시일 내에 고쳐질 예정입니다.

## Auto-installer Download | 자동설치기 다운로드

https://github.com/sbrothers7/UMMInstall/releases/tag/v1.0.0

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

- **v3.x+ (Unity 6):** uses [kkorenn/unity-mod-manager](https://github.com/kkorenn/unity-mod-manager)'s `MacTuiInstaller`, which is built once and cached at `~/.cache/adofai-umm-installer/`.
- **v3.x+ (Unity 6):** [kkorenn/unity-mod-manager](https://github.com/kkorenn/unity-mod-manager)의 `MacTuiInstaller`를 사용하며, 한 번만 빌드되어 `~/.cache/adofai-umm-installer/`에 캐시됩니다.
