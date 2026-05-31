import SwiftUI

struct UpdatingView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(vm.subtitle.isEmpty
                 ? vm.t("Checking for updates…", "업데이트 확인 중…")
                 : vm.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
