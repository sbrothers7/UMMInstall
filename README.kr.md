# macOS 얼불춤 모드 딸깍설치기

[English](README.md) | 한국어

[A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/)용 [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM) 또는 [MelonLoader](https://melonwiki.xyz/) (v3.x+ 권장)의 네이티브 macOS 설치기입니다. 레거시 Unity 2022 빌드 (v2.x)와 현재 Unity 6 빌드 (v3.x+) 모두를 지원합니다.

> [!Note]
> JALib을 필요로 하는 모드 (지퍼 리소스펙, PACL, BetterCalibration, 등)는 macOS의 MelonLoader에서 지원됩니다 (Apple Silicon 포함).

## 자동설치기 다운로드

https://github.com/sbrothers7/UMMInstall/releases/latest

- macOS: `Installer-macos.zip`
- Linux (x64): `Installer-linux.tar.gz`. 원하는 곳에 압축을 풀고 `adofai-mod-installer/adofai_mod_installer`를 실행하세요. 처음 실행하면 앱 메뉴에 추가됩니다. GTK 3이 필요하며, 대부분의 데스크톱에 기본으로 설치되어 있습니다.

## 커맨드 라인 (amm)

```
curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/cli/install.sh | bash
```

| 명령어 | 설명 |
|---|---|
| `amm install` | 기본 로더 설치 (이미 설치되어 있으면 상태 표시) |
| `amm install --ml` / `--native` / `--rosetta` | MelonLoader / UMM 네이티브 / UMM Rosetta 설치 |
| `amm install --umm` | 기존 패치 방식으로 UMM 설치 (`--rosetta`와 같음, Apple Silicon Mac에서만 Rosetta 사용) |
| `amm reinstall` | 현재 로더 재설치 |
| `amm reinstall --<method>` | 다른 방식으로 재설치 |
| `amm uninstall` | 로더 제거 |
| `amm default [method]` | 기본 로더 확인 또는 설정 |
| `amm status` | 게임, 로더, 모드 개수 확인 |
| `amm list` / `-l` | 설치된 모드 목록 |
| `amm search [text]` / `-s` | 모드 검색 (텍스트 없이 실행하면 모든 모드와 버전, 게임 버전 표시) |
| `amm install --mod <mod>` / `mi` | 모드 설치 |
| `amm mr <mod>` (`--keep`) | 모드 제거 (`--keep`은 설정 유지) |
| `amm upgrade` | 설치된 모든 모드 업그레이드 |
| `amm upgrade <slug>` | 모드 하나 업그레이드 |
| `amm update` | amm, ammtui, GUI 앱(응용 프로그램 폴더, Linux는 앱 메뉴에 있는 것)을 최신 릴리스로 업데이트 |

`ammtui`는 대화형 메뉴를 엽니다. `-y`를 붙이면 확인을 건너뜁니다. Linux(x64)에서는 네이티브 빌드에서 MelonLoader(권장) 또는 UMM(`--umm`)을 지원하며, UMM에는 `mono`와 `expect`가 필요합니다 (예: `sudo apt install mono-complete expect`).


## 요구 사항

- macOS 13+
- 기본 경로(`~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice`)에 설치된 Steam 버전 ADOFAI

설치기는 필요할 경우 [Homebrew](https://brew.sh)와 `git`, `dotnet`, `mono`, `expect`, `wget`을 자동으로 설치합니다. Homebrew 설치 중 비밀번호를 묻는 메시지가 표시될 수 있습니다.

[추가 정보](INFO.kr.md)
