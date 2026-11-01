# macOS 얼불춤 모드 딸깍설치기

[English](README.md) | 한국어

[A Dance of Fire and Ice](https://store.steampowered.com/app/977950/A_Dance_of_Fire_and_Ice/)용 [Unity Mod Manager](https://www.nexusmods.com/site/mods/21) (UMM) 또는 [MelonLoader](https://melonwiki.xyz/) (v3.x+ 권장)의 네이티브 macOS 설치기입니다. 레거시 Unity 2022 빌드 (v2.x)와 현재 Unity 6 빌드 (v3.x+) 모두를 지원합니다.

> [!Note]
> 현재 JALib을 필요로 하는 모드 (지퍼 리소스펙, PACL, BetterCalibration, 등)는 v3에서 사용이 불가합니다. 빠른 시일 내에 고쳐질 예정입니다.

## 자동설치기 다운로드

https://github.com/sbrothers7/UMMInstall/releases/latest

## 커맨드 라인 (amm)

```
curl -fsSL https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/cli/install.sh | bash
```

| 명령어 | 설명 |
|---|---|
| `amm install` | 기본 로더 설치 (이미 설치되어 있으면 상태 표시) |
| `amm install --ml` / `--native` / `--rosetta` | MelonLoader / UMM 네이티브 / UMM Rosetta 설치 |
| `amm reinstall` | 현재 로더 재설치 |
| `amm reinstall --<method>` | 다른 방식으로 재설치 |
| `amm uninstall` | 로더 제거 |
| `amm default [method]` | 기본 로더 확인 또는 설정 |
| `amm status` | 게임, 로더, 모드 개수 확인 |
| `amm list` / `-l` | 설치된 모드 목록 |
| `amm search [text]` / `-s` | 모드 검색 (텍스트 없이 실행하면 모든 모드와 버전, 게임 버전 표시) |
| `amm modinstall <mod>` / `mi` | 모드 설치 |
| `amm mr <mod>` (`--keep`) | 모드 제거 (`--keep`은 설정 유지) |
| `amm upgrade` | 설치된 모든 모드 업그레이드 |
| `amm upgrade <slug>` | 모드 하나 업그레이드 |
| `amm update` | amm, ammtui, GUI 앱(응용 프로그램 폴더)을 최신 릴리스로 업데이트 |

`ammtui`는 대화형 메뉴를 엽니다. `-y`를 붙이면 확인을 건너뜁니다. Linux(x64)에서는 네이티브 빌드의 MelonLoader만 지원합니다.


## 요구 사항

- macOS 13+
- 기본 경로(`~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice`)에 설치된 Steam 버전 ADOFAI

설치기는 필요할 경우 [Homebrew](https://brew.sh)와 `git`, `dotnet`, `mono`, `expect`, `wget`을 자동으로 설치합니다. Homebrew 설치 중 비밀번호를 묻는 메시지가 표시될 수 있습니다.

[추가 정보](INFO.kr.md)
