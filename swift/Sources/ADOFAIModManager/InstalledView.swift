import SwiftUI

struct InstalledView: View {
    @EnvironmentObject var vm: InstallerViewModel
    @State private var confirmingUninstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.t("Unity Mod Manager is installed",
                          "Unity Mod Manager가 설치되어 있습니다"))
                    .font(.title2.bold())
                if let v = vm.gameVersion {
                    Text(vm.t("Detected ADOFAI \(v)", "감지된 ADOFAI 버전: \(v)"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text(vm.t("ADOFAI version not detected",
                              "ADOFAI 버전을 감지하지 못했습니다"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button {
                    vm.proceedFromInstalled()
                } label: {
                    Label(vm.t("Install Mods", "모드 설치"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button {
                    confirmingUninstall = true
                } label: {
                    Label(vm.t("Uninstall Unity Mod Manager", "Unity Mod Manager 제거"), systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button(vm.t("Close", "닫기")) { vm.cancelInstall() }
            }
        }
        .padding(24)
        .alert(vm.t("Uninstall Unity Mod Manager?",
                    "Unity Mod Manager를 제거하시겠습니까?"),
               isPresented: $confirmingUninstall) {
            Button(vm.t("Cancel", "취소"), role: .cancel) {}
            Button(vm.t("Uninstall", "제거"), role: .destructive) { vm.startUninstall() }
        } message: {
            Text(vm.t("This will restore the patched game files. Installed mods in the Mods folder will be left in place.",
                      "패치된 게임 파일이 복원됩니다. Mods 폴더에 설치된 모드는 그대로 유지됩니다."))
        }
    }
}
