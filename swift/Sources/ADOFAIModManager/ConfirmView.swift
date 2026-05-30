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
                Spacer()
                Button(vm.t("Cancel", "취소")) { vm.cancelInstall() }
                Button(vm.t("Proceed", "계속")) { vm.proceedFromConfirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
