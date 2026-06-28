# 추가 정보

## 터미널

```bash
./adofai-umm.sh             # 설치
./adofai-umm-uninstall.sh   # 제거
```

설치 후, Steam을 통해 게임을 실행하고 UMM 메뉴를 열려면 **Ctrl+F10**을 누르세요.

## 소스에서 빌드 (Swift GUI 애플리케이션)

SwiftUI 앱을 빌드합니다:

```bash
cd swift
./build.sh                              # 호스트 아키텍처; Swift CLI 도구 필요
./build.sh --version 1.0.10              # 번들 버전 설정 (GitHub 릴리스 태그와 일치)
./build.sh --version 1.0.10 --zip        # 배포용 .zip 생성
UNIVERSAL=1 ./build.sh --version 1.0.10  # 유니버설 arm64 + x86_64 (Xcode 필요)
```

## 버전별 참고 사항

- **v2.x (Unity 2022):** Mono에서 UMM의 `Console.exe`를 통해 `UnityEngine.CoreModule.dll`을 패치하며, Apple Silicon에서는 게임 바이너리의 arm64 슬라이스를 제거하여 Rosetta에서 실행되도록 합니다 (이 빌드의 UMM 런타임은 x86_64 전용). 제거 후 arm64 슬라이스를 완전히 복원하려면 Steam → 속성 → 설치 파일에서 게임 파일 무결성을 검증하세요.

- **v3.x+ (Unity 6):** [kkorenn/unity-mod-manager](https://github.com/kkorenn/unity-mod-manager)의 `MacTuiInstaller`를 사용하며, 한 번만 빌드되어 `~/.cache/adofai-umm-installer/`에 캐시됩니다. Apple Silicon에서는 Steam.app이 "Rosetta를 사용하여 열기"로 설정되어 있지 않은지 확인하세요 (Steam.app → 정보 가져오기) — Steam이 Rosetta로 실행되면 네이티브 설치 프로그램이 실패합니다.

## GUI 기능

- **실행 시 자동 업데이트:** 앱은 실행할 때마다 GitHub 릴리스를 확인하고, 새 버전이 있으면 자체적으로 교체합니다 (수동 다운로드 불필요).

- **앱 내 Homebrew 설치:** Homebrew가 없는 경우 macOS 네이티브 인증 대화상자가 한 번만 표시됩니다. 설치 프로그램은 사용자 권한으로 실행되어 (임시 sudoers 엔트리 사용) 출력이 UMM과 동일한 진행 로그에 표시됩니다. 터미널 팝업이나 앱 재실행이 필요하지 않습니다.

- **MelonLoader 지원:** v3.x+에서는 UMM 대신 [MelonLoader](https://melonwiki.xyz/)(권장)를 설치할 수 있습니다 — UMMCompat 플러그인(square3ang)을 자동 설치하고, Steam 실행 옵션을 대신 설정하며, 모드를 `UMMMods/`에 설치합니다. UMM이 이미 설치되어 있으면 마이그레이션(UMM 제거, MelonLoader 설치, 기존 UMM 모드를 `UMMMods/`로 이동)을 안내합니다. 전용 MelonLoader 빌드를 제공하는 모드(예: Quartz)는 MelonLoader가 활성 로더일 때 자동으로 해당 빌드를 사용합니다.

- **모드 선택기:** 게임 버전에 맞는 호환 릴리스를 자동으로 선택합니다. v3 호환 릴리스가 없는 모드는 v3.x+에서 숨겨지며, v2 지원이 중단된 모드는 v2.x에서 고정된 이전 빌드로 폴백됩니다.

## 모드 목록 업데이트

모드 선택기는 실행 시 이 저장소에서 가져오는 [mods.json](mods.json)으로 동작합니다 — 파일을 수정하고 푸시하면 **앱을 다시 빌드하지 않고** 모드 목록을 변경할 수 있습니다. 각 항목:

- `id` — 표시 이름.
- `url` — 기본 다운로드.
- `urlV2` (선택) — v2.x 빌드에서 사용하는 다운로드.
- `urlMelon` (선택) — 활성 로더가 MelonLoader일 때 사용하는 다운로드.
- `v2` / `v3` (기본값 `true`) — 게임 빌드별 제공 여부.
- `jalib` (기본값 `false`) — JALib 의존 모드가 작동하지 않는 동안 배너와 함께 숨김.
- `install` (선택) — 특수 설치 핸들러 키 (예: `quartz` — MelonLoader/UMM 빌드 모두에 대해 플러그인 DLL과 데이터 폴더 배치).
