import SwiftUI

struct NeedsVerifyView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 18))
                Text(vm.t("Verify game files in Steam first",
                          "먼저 Steam에서 게임 파일 무결성을 확인해 주세요"))
                    .font(.title2.bold())
            }

            Text(vm.t(
                "The arm64 slice of the game binary is missing. This usually means UMM was previously installed and the slice was stripped for Rosetta. Restore the original universal binary before installing on this Unity 6 build.",
                "게임 바이너리의 arm64 슬라이스가 없습니다. 이전에 UMM이 설치되면서 Rosetta 실행용으로 제거된 것으로 보입니다. 이 Unity 6 빌드에 설치하기 전에 원본 유니버설 바이너리를 복원해야 합니다."
            ))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(vm.t("How to verify:", "확인 방법:"))
                    .font(.system(size: 13, weight: .semibold))
                Text(vm.t(
                    """
                    1. Click “Open Steam to Verify” below (or open Steam manually).
                    2. Right-click “A Dance of Fire and Ice” → Properties.
                    3. Installed Files → Verify integrity of game files.
                    4. When Steam finishes, click “Check Again”.
                    """,
                    """
                    1. 아래 “Steam에서 확인 열기”를 누릅니다 (또는 Steam을 직접 엽니다).
                    2. 라이브러리에서 “A Dance of Fire and Ice”를 우클릭 → 속성.
                    3. 설치된 파일 → 게임 파일 무결성 확인.
                    4. Steam이 끝나면 “다시 확인”을 누릅니다.
                    """
                ))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button(vm.t("Check Again", "다시 확인")) { vm.bootstrap() }
                Spacer()
                Button(vm.t("Close", "닫기")) { vm.cancelInstall() }
                Button(vm.t("Open Steam to Verify", "Steam에서 확인 열기")) {
                    vm.openSteamVerify()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}
