# macOS ADOFAI Mod Installer | macOS 얼불춤 모드 딸깍설치기

A native macOS installer for [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM) on [A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/). Handles both the legacy Unity 2022 build (v2.x) and the current Unity 6 build (v3.x+), and bundles a mod select/installer.

[A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/)용 [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM)의 네이티브 macOS 설치기입니다. 레거시 Unity 2022 빌드 (v2.x)와 현재 Unity 6 빌드 (v3.x+) 모두를 지원합니다.

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

The installer auto-installs [Homebrew](https://brew.sh) (if needed) and any of `git`, `dotnet`, `mono`, `expect`, `wget` it needs. You may be prompted for your password during the Homebrew install.

설치기는 필요할 경우 [Homebrew](https://brew.sh)와 `git`, `dotnet`, `mono`, `expect`, `wget`을 자동으로 설치합니다. Homebrew 설치 중 비밀번호를 묻는 메시지가 표시될 수 있습니다.

[More Info | 추가 정보](https://github.com/sbrothers7/UMMInstall/blob/main/INFO.md)
