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
    @Published var selectedLoader: LoaderType = .umm
    @Published var migratableMods: [String] = []
    @Published var mods: [Mod] = []
    @Published var modsError: String?
    @Published var language: Language =
        Language(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .en {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    static let gamePath = (("~/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice") as NSString).expandingTildeInPath
    static let gameAppPath = gamePath + "/ADanceOfFireAndIce.app"
    static let ummModsPath = gamePath + "/Mods"
    static let melonModsPath = gamePath + "/UMMMods"
    static let ummMarkerPath = gameAppPath + "/Contents/Resources/Data/Managed/UnityModManager/UnityModManager.dll"
    static let melonLoaderMarkerPath = gamePath + "/MelonLoader.Bootstrap.dylib"
    static let bashInstallURL = "https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/adofai-umm.sh"
    static let bashUninstallURL = "https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/adofai-umm-uninstall.sh"
    static let melonInstallURL = "https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/adofai-melonloader.sh"
    static let melonUninstallURL = "https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/adofai-melonloader-uninstall.sh"

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
            // Network down / rate-limited / un-writable install location, etc.
            // Fall through to normal launch rather than quitting into a loop.
            NSLog("ADOFAI updater: skipping update — \(error.localizedDescription)")
        }
        // Pull the mod list from the repo so the picker reflects registry edits
        // without an app rebuild.
        await loadMods()
        subtitle = ""
        continueBootstrap()
    }

    func loadMods() async {
        do {
            mods = try await ModRegistry.fetch()
            modsError = nil
        } catch {
            mods = []
            modsError = error.localizedDescription
            NSLog("ADOFAI: failed to load mod list — \(error.localizedDescription)")
        }
    }

    func reloadMods() {
        Task { await loadMods() }
    }

    private func continueBootstrap() {
        detectGameVersion()
        if hasMelonLoader() || isUMMInstalled() {
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

    func hasMelonLoader() -> Bool {
        FileManager.default.fileExists(atPath: Self.melonLoaderMarkerPath)
    }

    var modsInstallPath: String {
        hasMelonLoader() ? Self.melonModsPath : Self.ummModsPath
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

    /// Mods shown in the picker for the detected game version. JALib-dependent
    /// mods are hidden (and surfaced via the banner) while JALib is broken.
    var visibleMods: [Mod] {
        mods.filter { mod in
            guard !mod.jalib else { return false }
            return isGameV2 ? mod.v2 : mod.v3
        }
    }

    /// JALib-dependent mods that would otherwise be available for this game
    /// version — listed in the picker's "unavailable" banner.
    var unavailableJALibMods: [Mod] {
        mods.filter { $0.jalib && (isGameV2 ? $0.v2 : $0.v3) }
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
                Detected ADOFAI \(v). Choose a loader below.

                Native UMM (Unity Mod Manager):
                  • Installs Homebrew, git, .NET SDK (if not installed)
                  • Builds the MacTuiInstaller from kkorenn/unity-mod-manager and patches the game
                  • ⚠️ Disable "Open using Rosetta" on Steam.app first, or the install fails

                MelonLoader (recommended):
                  • Downloads MelonLoader 0.7.3 (macOS) from kkorenn/MelonLoader
                  • Auto-installs the UMMCompat plugin (square3ang) and sets Steam launch options for you
                  • No Homebrew or .NET needed
                  • Mods go into UMMMods/ (loaded by UMMCompat)
                """,
                """
                ADOFAI \(v) 감지됨. 아래에서 로더를 선택하세요.

                네이티브 UMM (Unity Mod Manager):
                  • Homebrew, git, .NET SDK 설치 (설치되지 않은 경우)
                  • kkorenn/unity-mod-manager의 MacTuiInstaller를 빌드하여 게임을 패치
                  • ⚠️ Steam.app의 "Rosetta를 사용하여 열기"를 먼저 해제해야 합니다

                MelonLoader (권장):
                  • kkorenn/MelonLoader에서 MelonLoader 0.7.3 (macOS) 다운로드
                  • UMMCompat 플러그인(square3ang)과 Steam 실행 옵션을 자동으로 설정합니다
                  • Homebrew나 .NET 필요 없음
                  • 모드는 UMMMods/ 폴더에 설치됩니다 (UMMCompat가 로드)
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

                ⚠️ On Apple Silicon, make sure Steam is NOT set to "Open using Rosetta" (right-click Steam.app → Get Info). The native installer fails if Steam runs under Rosetta.
                """,
                """
                ADOFAI 버전을 감지하지 못했습니다 — 기본 네이티브 설치 프로그램을 사용합니다.

                다음을 설치합니다:
                  • Homebrew (설치되지 않은 경우)
                  • git, .NET SDK (설치되지 않은 경우)

                kkorenn/unity-mod-manager의 네이티브 MacTuiInstaller를 내려받아 빌드한 후 실행하여 게임을 패치합니다.

                ⚠️ Apple Silicon에서는 Steam.app이 "Rosetta를 사용하여 열기"로 설정되어 있지 않은지 확인하세요 (Steam.app 우클릭 → 정보 가져오기). Steam이 Rosetta로 실행되면 네이티브 설치 프로그램이 실패합니다.
                """
            )
        }
    }

    func proceedFromConfirm(with loader: LoaderType = .umm) {
        selectedLoader = loader
        phase = .picker
    }

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

    func startMigration() {
        selectedLoader = .melonLoader
        subtitle = t("Migrating to MelonLoader…", "MelonLoader로 마이그레이션 중…")
        phase = .migrating
        Task { await runMigration() }
    }

    func proceedFromInstalled() { phase = .picker }

    private func append(_ level: LogLevel, _ message: String) {
        logEntries.append(LogEntry(level: level, message: message))
    }

    private func applySteamLaunchOptions() {
        let helperPath = Self.gamePath + "/setup_helper.sh"
        let manual = "\"\(helperPath)\" %command%"
        switch SteamConfig.setLaunchOptions(setupHelperPath: helperPath) {
        case .updated(let count, let steamRunning):
            append(.ok, t("Steam launch options set (\(count) account\(count == 1 ? "" : "s")).",
                          "Steam 실행 옵션을 설정했습니다 (\(count)개 계정)."))
            if steamRunning {
                append(.info, t("Fully quit and reopen Steam for the launch options to take effect.",
                                "실행 옵션을 적용하려면 Steam을 완전히 종료한 후 다시 여세요."))
            }
        case .noConfigFound:
            append(.info, t("Couldn't set Steam launch options automatically — set them manually:",
                            "Steam 실행 옵션을 자동으로 설정하지 못했습니다 — 수동으로 설정하세요:"))
            append(.detail, manual)
        case .failed(let msg):
            append(.error, t("Failed to set Steam launch options.", "Steam 실행 옵션 설정 실패."))
            append(.detail, msg)
            append(.info, t("Set them manually:", "수동으로 설정하세요:"))
            append(.detail, manual)
        }
    }

    private func clearSteamLaunchOptions() {
        switch SteamConfig.clearLaunchOptions() {
        case .updated(let count, let steamRunning):
            guard count > 0 else { return }
            append(.ok, t("Cleared Steam launch options (\(count) account\(count == 1 ? "" : "s")).",
                          "Steam 실행 옵션을 지웠습니다 (\(count)개 계정)."))
            if steamRunning {
                append(.info, t("Fully quit and reopen Steam for this to take effect.",
                                "적용하려면 Steam을 완전히 종료한 후 다시 여세요."))
            }
        case .noConfigFound, .failed:
            break
        }
    }

    private func brewIsInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
    }

    private func ensureBrewInstalled(continuationPhase: InstallPhase) async -> Bool {
        if brewIsInstalled() { return true }

        let resumePhase = phase
        phase = .installingBrew
        subtitle = t("Installing Homebrew…", "Homebrew 설치 중…")
        append(.info, t("Homebrew not found — installing (you'll be asked for your password)…",
                        "Homebrew가 설치되지 않음 — 설치를 시작합니다 (비밀번호를 묻습니다)…"))
        do {
            try await BrewInstaller.install { [weak self] line in
                Task { @MainActor in self?.handleScriptLine(line) }
            }
            append(.ok, t("Homebrew installed.", "Homebrew 설치 완료."))
            phase = resumePhase
            subtitle = continuationPhase == .uninstalling
                ? t("Uninstalling…", "제거 중…")
                : t("Installing…", "설치 중…")
            return true
        } catch BrewInstaller.InstallError.authCancelled {
            append(.error, t("Authorization cancelled — Homebrew was not installed.",
                             "인증이 취소되었습니다 — Homebrew가 설치되지 않았습니다."))
            phase = .complete(success: false, message: t("Homebrew install cancelled.",
                                                         "Homebrew 설치 취소됨."))
            return false
        } catch {
            append(.error, t("Homebrew install failed.", "Homebrew 설치 실패."))
            append(.detail, error.localizedDescription)
            phase = .complete(success: false, message: t("Homebrew install failed.",
                                                         "Homebrew 설치 실패."))
            return false
        }
    }

    private func runInstall() async {
        if hasMelonLoader() {
            append(.info, t("MelonLoader detected — skipping loader install (use the UMMCompat plugin).",
                            "MelonLoader 감지됨 — 로더 설치를 건너뜁니다 (UMMCompat 플러그인 사용)."))
            append(.info, t("Mods will be installed into UMMMods/.",
                            "모드는 UMMMods/ 폴더에 설치됩니다."))
        } else if isUMMInstalled() {
            append(.info, t("Unity Mod Manager already installed — skipping.",
                            "Unity Mod Manager가 이미 설치됨 — 건너뜁니다."))
        } else {
            let isMelon = selectedLoader == .melonLoader
            if !isMelon {
                if !(await ensureBrewInstalled(continuationPhase: .installing)) { return }
            }

            let loaderName = isMelon ? "MelonLoader" : "Unity Mod Manager"
            let scriptURL = isMelon ? Self.melonInstallURL : Self.bashInstallURL
            let scriptFile = isMelon ? "~/.adofai-melonloader.sh" : "~/.adofai-umm.sh"
            let scriptPath = (scriptFile as NSString).expandingTildeInPath

            append(.info, t("Downloading installer…", "설치 프로그램 다운로드 중…"))
            do {
                try await Network.downloadFile(from: scriptURL, to: scriptPath)
            } catch {
                append(.error, t("Failed to download installer script.",
                                 "설치 스크립트 다운로드 실패."))
                append(.detail, error.localizedDescription)
                phase = .complete(success: false, message: t("Installation failed.", "설치 실패."))
                return
            }

            append(.info, t("Installing \(loaderName) (this may take a few minutes)…",
                            "\(loaderName) 설치 중 (몇 분 소요될 수 있습니다)…"))
            let runner = ScriptRunner()
            let exit = await runner.run(scriptPath: scriptPath) { [weak self] line in
                Task { @MainActor in self?.handleScriptLine(line) }
            }
            try? FileManager.default.removeItem(atPath: scriptPath)

            if exit != 0 {
                append(.error, t("\(loaderName) installation failed.",
                                 "\(loaderName) 설치 실패."))
                if !isMelon && !isGameV2 && isAppleSilicon() {
                    append(.info, t(
                        "If Steam is set to \"Open using Rosetta\" (Steam.app → Get Info), disable it and try again.",
                        "Steam이 \"Rosetta를 사용하여 열기\"로 설정되어 있다면 (Steam.app → 정보 가져오기), 해제 후 다시 시도하세요."))
                }
                phase = .complete(success: false, message: t("Installation failed.", "설치 실패."))
                return
            }
            append(.ok, t("\(loaderName) installed.", "\(loaderName) 설치 완료."))
        }

        // For the MelonLoader flow, point Steam's launch options at the wrapper
        // script so the loader actually injects on launch.
        if hasMelonLoader() {
            applySteamLaunchOptions()
        }

        let modsDir = modsInstallPath
        try? FileManager.default.createDirectory(atPath: modsDir, withIntermediateDirectories: true)
        var failed: [String] = []
        let selected = mods.filter { selectedMods.contains($0.id) }
        for (idx, mod) in selected.enumerated() {
            let i = idx + 1
            let n = selected.count
            append(.info, t("Downloading \(mod.id) (\(i)/\(n))…",
                            "\(mod.id) 다운로드 중 (\(i)/\(n))…"))
            do {
                try await ModDownloader.install(mod: mod, isGameV2: isGameV2, into: modsDir)
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
        // Choose the script based on what's actually installed, not the user's
        // current loader choice.
        let isMelon = hasMelonLoader()
        let loaderName = isMelon ? "MelonLoader" : "Unity Mod Manager"
        let scriptURL = isMelon ? Self.melonUninstallURL : Self.bashUninstallURL
        let scriptFile = isMelon ? "~/.adofai-melonloader-uninstall.sh" : "~/.adofai-umm-uninstall.sh"
        let scriptPath = (scriptFile as NSString).expandingTildeInPath

        // The UMM uninstaller calls brew tools (mono/expect/wget for v2.x,
        // git/dotnet for v3.x); the MelonLoader uninstaller is just file rm.
        if !isMelon {
            if !(await ensureBrewInstalled(continuationPhase: .uninstalling)) { return }
        }

        append(.info, t("Downloading uninstaller…", "제거 프로그램 다운로드 중…"))
        do {
            try await Network.downloadFile(from: scriptURL, to: scriptPath)
        } catch {
            append(.error, t("Failed to download uninstaller script.",
                             "제거 스크립트 다운로드 실패."))
            append(.detail, error.localizedDescription)
            phase = .complete(success: false, message: t("Uninstall failed.", "제거 실패."))
            return
        }

        append(.info, t("Uninstalling \(loaderName)…", "\(loaderName) 제거 중…"))
        let runner = ScriptRunner()
        let exit = await runner.run(scriptPath: scriptPath) { [weak self] line in
            Task { @MainActor in self?.handleScriptLine(line) }
        }
        try? FileManager.default.removeItem(atPath: scriptPath)

        if exit != 0 {
            append(.error, t("\(loaderName) uninstall failed.", "\(loaderName) 제거 실패."))
            phase = .complete(success: false, message: t("Uninstall failed.", "제거 실패."))
            return
        }
        append(.ok, t("\(loaderName) uninstalled.", "\(loaderName) 제거 완료."))

        // Undo the Steam launch options we set for the MelonLoader wrapper.
        if isMelon {
            clearSteamLaunchOptions()
        }

        phase = .complete(success: true, message: t("Uninstall complete.", "제거 완료."))
    }

    // MARK: - UMM → MelonLoader migration

    private func downloadAndRunScript(url: String, file: String) async -> Int32 {
        let scriptPath = (file as NSString).expandingTildeInPath
        do {
            try await Network.downloadFile(from: url, to: scriptPath)
        } catch {
            append(.error, t("Failed to download script.", "스크립트 다운로드 실패."))
            append(.detail, error.localizedDescription)
            return -1
        }
        let runner = ScriptRunner()
        let exit = await runner.run(scriptPath: scriptPath) { [weak self] line in
            Task { @MainActor in self?.handleScriptLine(line) }
        }
        try? FileManager.default.removeItem(atPath: scriptPath)
        return exit
    }

    private func runMigration() async {
        // 1. Uninstall UMM (its uninstaller needs brew tools).
        if !(await ensureBrewInstalled(continuationPhase: .migrating)) { return }
        append(.info, t("Removing Unity Mod Manager…", "Unity Mod Manager 제거 중…"))
        let ummExit = await downloadAndRunScript(url: Self.bashUninstallURL, file: "~/.adofai-umm-uninstall.sh")
        if ummExit != 0 {
            append(.error, t("Failed to remove Unity Mod Manager.", "Unity Mod Manager 제거 실패."))
            phase = .complete(success: false, message: t("Migration failed.", "마이그레이션 실패."))
            return
        }
        append(.ok, t("Unity Mod Manager removed.", "Unity Mod Manager 제거 완료."))

        // 2. Install MelonLoader (+ UMMCompat + launch options).
        subtitle = t("Installing MelonLoader…", "MelonLoader 설치 중…")
        append(.info, t("Installing MelonLoader…", "MelonLoader 설치 중…"))
        let melonExit = await downloadAndRunScript(url: Self.melonInstallURL, file: "~/.adofai-melonloader.sh")
        if melonExit != 0 {
            append(.error, t("MelonLoader installation failed.", "MelonLoader 설치 실패."))
            phase = .complete(success: false, message: t("Migration failed.", "마이그레이션 실패."))
            return
        }
        append(.ok, t("MelonLoader installed.", "MelonLoader 설치 완료."))
        if hasMelonLoader() { applySteamLaunchOptions() }

        // 3. If old UMM mods remain in Mods/, prompt to move them to UMMMods/.
        let found = findUMMModsInModsFolder()
        if found.isEmpty {
            phase = .complete(success: true, message: t("Migration complete.", "마이그레이션 완료."))
        } else {
            migratableMods = found
            subtitle = t("Migration almost done…", "마이그레이션 거의 완료…")
            phase = .confirmModMove
        }
    }

    /// UMM mods are folders under Mods/ that contain an info.json.
    private func findUMMModsInModsFolder() -> [String] {
        let fm = FileManager.default
        let modsDir = Self.ummModsPath
        guard let entries = try? fm.contentsOfDirectory(atPath: modsDir) else { return [] }
        return entries.filter { name in
            if name.hasPrefix(".") { return false }
            let full = modsDir + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { return false }
            let contents = (try? fm.contentsOfDirectory(atPath: full)) ?? []
            return contents.contains { $0.lowercased() == "info.json" }
        }.sorted()
    }

    func moveMigratableMods() {
        let fm = FileManager.default
        let src = Self.ummModsPath
        let dst = Self.melonModsPath
        try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        var moved = 0
        for name in migratableMods {
            let from = src + "/" + name
            let to = dst + "/" + name
            do {
                if fm.fileExists(atPath: to) { try fm.removeItem(atPath: to) }
                try fm.moveItem(atPath: from, toPath: to)
                moved += 1
            } catch {
                append(.error, t("Failed to move \(name).", "\(name) 이동 실패."))
                append(.detail, error.localizedDescription)
            }
        }
        append(.ok, t("Moved \(moved) mod\(moved == 1 ? "" : "s") to UMMMods/.",
                      "\(moved)개 모드를 UMMMods/로 이동했습니다."))
        migratableMods = []
        phase = .complete(success: true, message: t("Migration complete.", "마이그레이션 완료."))
    }

    func skipMigratableMods() {
        migratableMods = []
        phase = .complete(success: true,
                          message: t("Migration complete. UMM mods left in Mods/ — move them to UMMMods/ to use them.",
                                     "마이그레이션 완료. UMM 모드는 Mods/에 남아 있습니다 — 사용하려면 UMMMods/로 옮기세요."))
    }

    private static let ansiCSI = try! NSRegularExpression(pattern: "\u{001B}\\[[\\d;?]*[a-zA-Z]")
    private static let ansiShort = try! NSRegularExpression(pattern: "\u{001B}[=>cm78]")
    private static let ansiCharset = try! NSRegularExpression(pattern: "\u{001B}[()][AB012]")
    private static let scriptHeader = try! NSRegularExpression(pattern: "\\^D\u{0008}+")
    // Progress meters (curl/wget/dotnet/git) that animate with `#` and a
    // percentage just spam the log — drop them. The spinner + subtitle already
    // convey activity.
    private static let progressLine = try! NSRegularExpression(
        pattern: "^[#\\s]*\\d{1,3}(\\.\\d+)?%[#\\s]*$|^#{3,}\\s*$")

    private func handleScriptLine(_ raw: String) {
        // A carriage-return-animated line (e.g. "a\rb\rc") displays only its
        // final frame; collapse to the last non-empty segment rather than
        // concatenating every frame into one giant line.
        var line = raw
        if line.contains("\r") {
            line = line.components(separatedBy: "\r").last(where: { !$0.isEmpty }) ?? ""
        }
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

        let fullRange = NSRange(line.startIndex..., in: line)
        if Self.progressLine.firstMatch(in: line, range: fullRange) != nil { return }

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
