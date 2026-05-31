import SwiftUI

struct ModPickerView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.t("ADOFAI Mod Installer", "ADOFAI 모드 설치기"))
                    .font(.title3.bold())
                Text(vm.t("Select mods to install with Unity Mod Manager",
                          "Unity Mod Manager로 설치할 모드를 선택하세요"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            HStack {
                Spacer()
                Button(allSelected ? vm.t("Deselect All", "모두 해제") : vm.t("Select All", "모두 선택")) {
                    toggleAll()
                }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(vm.visibleMods) { mod in
                        ModRow(mod: mod)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            HStack {
                Spacer()
                Button(vm.t("Cancel", "취소")) { vm.cancelInstall() }
                Button(vm.t("Skip Mods", "모드 건너뛰기")) { vm.startInstall(skipMods: true) }
                Button(vm.t("Install", "설치")) { vm.startInstall() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.selectedMods.isEmpty)
            }
            .padding(24)
        }
    }

    private var allSelected: Bool {
        vm.selectedMods.count == vm.visibleMods.count
    }

    private func toggleAll() {
        if allSelected {
            vm.selectedMods.removeAll()
        } else {
            vm.selectedMods = Set(vm.visibleMods.map { $0.id })
        }
    }
}

private struct ModRow: View {
    let mod: Mod
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        Button {
            if vm.selectedMods.contains(mod.id) {
                vm.selectedMods.remove(mod.id)
            } else {
                vm.selectedMods.insert(mod.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: vm.selectedMods.contains(mod.id) ? "checkmark.square.fill" : "square")
                    .foregroundColor(vm.selectedMods.contains(mod.id) ? .accentColor : .secondary)
                    .font(.system(size: 16))
                Text(mod.id)
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.001))
        )
    }
}
