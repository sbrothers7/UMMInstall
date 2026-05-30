import SwiftUI
import AppKit

struct InstallProgressView: View {
    @EnvironmentObject var vm: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.t("ADOFAI Mod Manager", "ADOFAI 모드 관리자"))
                    .font(.title3.bold())
                Text(progressSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.logEntries) { entry in
                            LogRow(entry: entry).id(entry.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: vm.logEntries.count) { _ in
                    if let last = vm.logEntries.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(vm.t("Close", "닫기")) { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.18))
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .top)
        }
    }

    private var progressSubtitle: String {
        switch vm.phase {
        case .installing, .uninstalling: return vm.subtitle
        case .complete(_, let msg):      return msg
        default:                         return ""
        }
    }

    private var canClose: Bool {
        if case .complete = vm.phase { return true }
        return vm.logEntries.contains { $0.level == .error }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        if entry.level == .detail {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 2)
                Text(entry.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 10)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 28)
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 16, alignment: .center)
                Text(entry.message)
                    .font(.system(size: 14))
                    .foregroundColor(bodyColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private var icon: String {
        switch entry.level {
        case .info:  return "›"
        case .ok:    return "✓"
        case .error: return "✕"
        default:     return ""
        }
    }

    private var iconColor: Color {
        switch entry.level {
        case .ok:    return Color(red: 0.32, green: 0.81, blue: 0.40)
        case .error: return Color(red: 1.00, green: 0.42, blue: 0.42)
        default:     return .secondary
        }
    }

    private var bodyColor: Color {
        switch entry.level {
        case .ok:    return Color(red: 0.70, green: 0.95, blue: 0.73)
        case .error: return Color(red: 1.00, green: 0.66, blue: 0.66)
        default:     return Color(red: 0.87, green: 0.88, blue: 0.90)
        }
    }
}
