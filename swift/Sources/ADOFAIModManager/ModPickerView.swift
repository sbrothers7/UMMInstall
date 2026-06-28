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

            if let error = vm.modsError {
                modListError(error)
            } else {
                if !vm.unavailableJALibMods.isEmpty {
                    jalibBanner
                        .padding(.horizontal, 24)
                        .padding(.bottom, 4)
                }

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

    private func modListError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(vm.t("Couldn't load the mod list.", "모드 목록을 불러오지 못했습니다."))
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(vm.t("Retry", "다시 시도")) { vm.reloadMods() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var jalibBanner: some View {
        let names = vm.unavailableJALibMods.map { $0.id }.joined(separator: ", ")
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(vm.t(
                "Mods that depend on JALib are temporarily unavailable and hidden: \(names).",
                "JALib을 필요로 하는 모드는 현재 사용할 수 없어 숨겨졌습니다: \(names)."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
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
