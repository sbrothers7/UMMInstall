import SwiftUI

struct ConfirmView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(vm.t("ADOFAI Mod Manager Installer", "ADOFAI 모드 관리자 설치"))
                .font(.title2.bold())
            ScrollView {
                Text(vm.confirmationText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            HStack {
                Button(vm.t("Cancel", "취소")) { vm.cancelInstall() }
                Spacer()
                if vm.isGameV2 {
                    Button(vm.t("Proceed", "계속")) { vm.proceedFromConfirm(with: .umm) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(vm.t("Native UMM", "네이티브 UMM")) { vm.proceedFromConfirm(with: .umm) }
                        .buttonStyle(.bordered)
                    Button(vm.t("MelonLoader", "MelonLoader")) { vm.proceedFromConfirm(with: .melonLoader) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
    }
}
