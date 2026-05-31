import SwiftUI
import Foundation
import AppKit

@MainActor
final class InstallerViewModel: ObservableObject {
    @Published var phase: InstallPhase = .updating
    @Published var gameVersion: String?
    @Published var logEntries: [LogEntry] = []
    @Published var subtitle: String = ""
    @Published var selectedMods: Set<String> = []
    @Published var language: Language =
        Language(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .en {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    static let gamePath = (("~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice") as NSString).expandingTildeInPath
    static let gameAppPath = gamePath + "/ADanceOfFireAndIce.app"
    static let modsPath = gamePath + "/Mods"
    static let ummMarkerPath = gameAppPath + "/Contents/Resources/Data/Managed/UnityModManager/UnityModManager.dll"
    static let bashInstallURL = "https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/adofai-umm.sh"
    static let bashUninstallURL = "https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/adofai-umm-uninstall.sh"

    func t(_ en: String, _ ko: String) -> String { language == .ko ? ko : en }

    func bootstrap() {
        subtitle = t("Checking for updates…", "업데이트 확인 중…")
        phase = .updating
        Task { await runUpdateCheckThenContinue() }
    }

    private func runUpdateCheckThenContinue() async {
        do {
            let latest = try await Updater.fetchLatest()
            if Updater.isNewer(latest.tag, than: Updater.currentVersion) {
                subtitle = t("Updating to \(latest.tag)…", "\(latest.tag) (으)로 업데이트 중…")
                try await Updater.performUpdate(downloadURL: latest.downloadURL)
                // performUpdate spawns a detached helper that will replace the
                // bundle and re-open it once we exit. Quit so the swap can run.
                await MainActor.run { NSApp.terminate(nil) }
                return
            }
        } catch {
            // Network down / rate-limited / malformed release — fall through.
        }
        subtitle = ""
        continueBootstrap()
    }

    private func continueBootstrap() {
        detectGameVersion()
        if isUMMInstalled() {
            phase = .installed
        } else if isAppleSilicon() && !isGameV2 && !hasArm64Slice() {
            phase = .needsVerify
        } else {
            phase = .confirm
        }
    }

    func isUMMInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.ummMarkerPath)
    }

    func isAppleSilicon() -> Bool {
        var ret: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &ret, &size, nil, 0) == 0 && ret == 1
    }

    func hasArm64Slice() -> Bool {
        let exePath = Self.gameAppPath + "/Contents/MacOS/ADanceOfFireAndIce"
        guard FileManager.default.fileExists(atPath: exePath) else { return true }
        let process = Process()
        process.launchPath = "/usr/bin/lipo"
        process.arguments = ["-info", exePath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return out.contains("arm64")
        } catch {
            return true
        }
    }

    func openSteamVerify() {
        if let url = URL(string: "steam://validate/977950") {
            NSWorkspace.shared.open(url)
        }
    }

    private func detectGameVersion() {
        let plist = Self.gameAppPath + "/Contents/Info.plist"
        guard FileManager.default.fileExists(atPath: plist) else {
            gameVersion = nil
            return
        }
        let process = Process()
        process.launchPath = "/usr/libexec/PlistBuddy"
        process.arguments = ["-c", "Print :CFBundleShortVersionString", plist]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            gameVersion = (raw?.isEmpty == false) ? raw : nil
        } catch {
            gameVersion = nil
        }
    }

    var isGameV2: Bool { gameVersion?.hasPrefix("2.") == true }

    // TEMP: these mods have no v3.1.0-compatible release yet (DesyncFix is now baked into the game). Hide them on v3.x+ until upstream ships updates.
    var visibleMods: [Mod] {
        if isGameV2 {
            return ModRegistry.all.filter { !$0.v3Only }
        }
        let v3Excluded: Set<String> = [
            "AdofaiTweaks", "TUFHelper", "XPerfect", "DesyncFix", "TogetherBootstrap"
        ]
        return ModRegistry.all.filter { !v3Excluded.contains($0.id) }
    }

    var confirmationText: String {
        let v = gameVersion ?? "?"
        if isGameV2 {
            return t(
                """
                Detected ADOFAI \(v) (Unity 2022 build).

                This script will install:
                  • Homebrew (if not installed)
                  • mono, expect, wget (if not installed)

                On Apple Silicon, the arm64 slice of the game binary will be stripped so Steam launches under Rosetta (required for Harmony JIT patching on this build).
                """,
                """
                ADOFAI \(v) (Unity 2022 빌드) 감지됨.

                다음을 설치합니다:
                  • Homebrew (설치되지 않은 경우)
                  • mono, expect, wget (설치되지 않은 경우)

                Apple Silicon에서는 Steam이 Rosetta로 실행되도록 게임 바이너리의 arm64 슬라이스가 제거됩니다 (이 빌드의 Harmony JIT 패치에 필요).
                """
            )
        } else if gameVersion != nil {
            return t(
                """
                Detected ADOFAI \(v) — using the native installer.

                This script will install:
                  • Homebrew (if not installed)
                  • git, .NET SDK (if not installed)

                The native MacTuiInstaller from kkorenn/unity-mod-manager will be fetched and built, then run to patch the game.
                """,
                """
                ADOFAI \(v) 감지됨 — 네이티브 설치 프로그램을 사용합니다.

                다음을 설치합니다:
                  • Homebrew (설치되지 않은 경우)
                  • git, .NET SDK (설치되지 않은 경우)

                kkorenn/unity-mod-manager의 네이티브 MacTuiInstaller를 내려받아 빌드한 후 실행하여 게임을 패치합니다.
                """
            )
        } else {
            return t(
                """
                ADOFAI version not detected — defaulting to native installer.

                This script will install:
                  • Homebrew (if not installed)
                  • git, .NET SDK (if not installed)

                The native MacTuiInstaller from kkorenn/unity-mod-manager will be fetched and built, then run to patch the game.
                """,
                """
                ADOFAI 버전을 감지하지 못했습니다 — 기본 네이티브 설치 프로그램을 사용합니다.

                다음을 설치합니다:
                  • Homebrew (설치되지 않은 경우)
                  • git, .NET SDK (설치되지 않은 경우)

                kkorenn/unity-mod-manager의 네이티브 MacTuiInstaller를 내려받아 빌드한 후 실행하여 게임을 패치합니다.
                """
            )
        }
    }

    func proceedFromConfirm() { phase = .picker }

    func cancelInstall() { NSApp.terminate(nil) }

    func startInstall(skipMods: Bool = false) {
        if skipMods { selectedMods.removeAll() }
        subtitle = t("Installing…", "설치 중…")
        phase = .installing
        Task { await runInstall() }
    }

    func startUninstall() {
        subtitle = t("Uninstalling…", "제거 중…")
        phase = .uninstalling
        Task { await runUninstall() }
    }

    func proceedFromInstalled() { phase = .picker }

    private func append(_ level: LogLevel, _ message: String) {
        logEntries.append(LogEntry(level: level, message: message))
    }

    private func brewIsInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
    }

    private func openTerminalForBrewInstall() {
        let cmd = #"/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""#
        let script = """
        tell application "Terminal"
            activate
            do script "\(cmd)"
        end tell
        """
        let osa = Process()
        osa.launchPath = "/usr/bin/osascript"
        osa.arguments = ["-e", script]
        try? osa.run()
    }

    private func emitBrewMissing(failureMessage: String) {
        append(.error, t("Homebrew is required but not installed.",
                         "Homebrew가 필요하지만 설치되어 있지 않습니다."))
        append(.info, t("A Terminal window has opened with the install command.",
                        "설치 명령이 입력된 터미널 창이 열렸습니다."))
        append(.info, t("After Homebrew finishes installing, re-launch this installer.",
                        "Homebrew 설치가 끝나면 이 프로그램을 다시 실행해 주세요."))
        openTerminalForBrewInstall()
        phase = .complete(success: false, message: failureMessage)
    }

    private func runInstall() async {
        if !brewIsInstalled() {
            emitBrewMissing(failureMessage: t("Homebrew install required.", "Homebrew 설치 필요."))
            return
        }

        append(.info, t("Downloading installer…", "설치 프로그램 다운로드 중…"))
        let scriptPath = (("~/.adofai-umm.sh") as NSString).expandingTildeInPath
        do {
            try await Network.downloadFile(from: Self.bashInstallURL, to: scriptPath)
        } catch {
            append(.error, t("Failed to download installer script.",
                             "설치 스크립트 다운로드 실패."))
            append(.detail, error.localizedDescription)
            phase = .complete(success: false, message: t("Installation failed.", "설치 실패."))
            return
        }

        append(.info, t("Installing Unity Mod Manager (this may take a few minutes)…",
                        "Unity Mod Manager 설치 중 (몇 분 소요될 수 있습니다)…"))
        let runner = ScriptRunner()
        let exit = await runner.run(scriptPath: scriptPath) { [weak self] line in
            Task { @MainActor in self?.handleScriptLine(line) }
        }
        try? FileManager.default.removeItem(atPath: scriptPath)

        if exit != 0 {
            append(.error, t("Unity Mod Manager installation failed.",
                             "Unity Mod Manager 설치 실패."))
            phase = .complete(success: false, message: t("Installation failed.", "설치 실패."))
            return
        }
        append(.ok, t("Unity Mod Manager installed.", "Unity Mod Manager 설치 완료."))

        try? FileManager.default.createDirectory(atPath: Self.modsPath, withIntermediateDirectories: true)
        var failed: [String] = []
        let mods = ModRegistry.all.filter { selectedMods.contains($0.id) }
        for (idx, mod) in mods.enumerated() {
            let i = idx + 1
            let n = mods.count
            append(.info, t("Downloading \(mod.id) (\(i)/\(n))…",
                            "\(mod.id) 다운로드 중 (\(i)/\(n))…"))
            do {
                try await ModDownloader.install(mod: mod, isGameV2: isGameV2, into: Self.modsPath)
                append(.ok, t("\(mod.id) installed.", "\(mod.id) 설치 완료."))
            } catch {
                append(.error, t("\(mod.id) failed to install.", "\(mod.id) 설치 실패."))
                append(.detail, error.localizedDescription)
                failed.append(mod.id)
            }
        }

        if failed.isEmpty {
            phase = .complete(success: true,
                              message: t("Installation complete.", "설치 완료."))
        } else {
            phase = .complete(success: false,
                              message: t("Installation finished with errors.",
                                         "오류와 함께 설치가 완료되었습니다."))
        }
    }

    private func runUninstall() async {
        if !brewIsInstalled() {
            emitBrewMissing(failureMessage: t("Homebrew install required.", "Homebrew 설치 필요."))
            return
        }

        append(.info, t("Downloading uninstaller…", "제거 프로그램 다운로드 중…"))
        let scriptPath = (("~/.adofai-umm-uninstall.sh") as NSString).expandingTildeInPath
        do {
            try await Network.downloadFile(from: Self.bashUninstallURL, to: scriptPath)
        } catch {
            append(.error, t("Failed to download uninstaller script.",
                             "제거 스크립트 다운로드 실패."))
            append(.detail, error.localizedDescription)
            phase = .complete(success: false, message: t("Uninstall failed.", "제거 실패."))
            return
        }

        append(.info, t("Uninstalling Unity Mod Manager…", "Unity Mod Manager 제거 중…"))
        let runner = ScriptRunner()
        let exit = await runner.run(scriptPath: scriptPath) { [weak self] line in
            Task { @MainActor in self?.handleScriptLine(line) }
        }
        try? FileManager.default.removeItem(atPath: scriptPath)

        if exit != 0 {
            append(.error, t("Unity Mod Manager uninstall failed.",
                             "Unity Mod Manager 제거 실패."))
            phase = .complete(success: false, message: t("Uninstall failed.", "제거 실패."))
            return
        }
        append(.ok, t("Unity Mod Manager uninstalled.", "Unity Mod Manager 제거 완료."))
        phase = .complete(success: true, message: t("Uninstall complete.", "제거 완료."))
    }

    private static let ansiCSI = try! NSRegularExpression(pattern: "\u{001B}\\[[\\d;?]*[a-zA-Z]")
    private static let ansiShort = try! NSRegularExpression(pattern: "\u{001B}[=>cm78]")
    private static let ansiCharset = try! NSRegularExpression(pattern: "\u{001B}[()][AB012]")
    private static let scriptHeader = try! NSRegularExpression(pattern: "\\^D\u{0008}+")

    private func handleScriptLine(_ raw: String) {
        var line = raw.replacingOccurrences(of: "\r", with: "")
        let stripping: (NSRegularExpression) -> Void = { regex in
            let range = NSRange(line.startIndex..., in: line)
            line = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        }
        stripping(Self.scriptHeader)
        stripping(Self.ansiCSI)
        stripping(Self.ansiShort)
        stripping(Self.ansiCharset)
        line = line.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return }

        if let colon = line.firstIndex(of: ":") {
            let prefix = line[..<colon].lowercased()
            let body = String(line[line.index(after: colon)...])
            switch prefix {
            case "info":     append(.info, body);   return
            case "ok":       append(.ok, body);     return
            case "error":    append(.error, body);  return
            case "detail":   append(.detail, body); return
            case "subtitle": subtitle = body;       return
            case "complete", "failed": return
            default: break
            }
        }
        append(.info, line)
    }
}

enum Network {
    static func downloadFile(from urlString: String, to path: String) async throws {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ADOFAIInstaller", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"])
        }
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "ADOFAIInstaller", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
