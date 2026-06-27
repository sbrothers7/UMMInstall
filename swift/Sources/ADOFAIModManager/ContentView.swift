import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        Group {
            switch vm.phase {
            case .updating:
                UpdatingView()
            case .confirm:
                ConfirmView()
            case .needsVerify:
                NeedsVerifyView()
            case .installed:
                InstalledView()
            case .picker:
                ModPickerView()
            case .installingBrew, .installing, .uninstalling, .migrating, .confirmModMove, .complete:
                InstallProgressView()
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            LanguagePicker()
                .padding(.top, 14)
                .padding(.trailing, 18)
        }
    }
}

private struct LanguagePicker: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        HStack(spacing: 6) {
            languageButton(.en, label: "EN")
            Text("/").foregroundStyle(.tertiary)
            languageButton(.ko, label: "KR")
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func languageButton(_ lang: Language, label: String) -> some View {
        Button(label) { vm.language = lang }
            .buttonStyle(.plain)
            .foregroundColor(vm.language == lang ? .primary : .secondary)
            .fontWeight(vm.language == lang ? .semibold : .regular)
    }
}
