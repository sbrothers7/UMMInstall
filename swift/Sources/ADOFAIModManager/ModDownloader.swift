import Foundation

enum ModDownloadError: LocalizedError {
    case httpError(Int)
    case unzipFailed(String)
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .unzipFailed(let msg): return "Unzip failed: \(msg)"
        case .emptyArchive:        return "Archive was empty"
        }
    }
}

enum ModDownloader {
    static func install(mod: Mod, isGameV2: Bool, isMelonLoader: Bool,
                        gameRoot: String, into modsDir: String) async throws {
        let tmpZip = "/tmp/adofai_mod_\(mod.id).zip"
        let tmpExtract = "/tmp/adofai_extract_\(mod.id)"
        let fm = FileManager.default

        defer {
            try? fm.removeItem(atPath: tmpZip)
            try? fm.removeItem(atPath: tmpExtract)
        }

        let url = mod.resolvedURL(isGameV2: isGameV2, isMelonLoader: isMelonLoader)
        try await Network.downloadFile(from: url, to: tmpZip)

        try? fm.removeItem(atPath: tmpExtract)
        try fm.createDirectory(atPath: tmpExtract, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.launchPath = "/usr/bin/unzip"
        unzip.arguments = ["-q", "-o", tmpZip, "-d", tmpExtract]
        let errPipe = Pipe()
        unzip.standardError = errPipe
        unzip.standardOutput = Pipe()
        try unzip.run()
        unzip.waitUntilExit()
        if unzip.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ModDownloadError.unzipFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let items = (try? fm.contentsOfDirectory(atPath: tmpExtract)) ?? []
        let visible = items.filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
        if visible.isEmpty { throw ModDownloadError.emptyArchive }

        if mod.install == "quartz" {
            try installQuartz(extractDir: tmpExtract, visible: visible, gameRoot: gameRoot)
            return
        }

        if visible.count == 1 {
            let first = visible[0]
            let firstPath = (tmpExtract as NSString).appendingPathComponent(first)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: firstPath, isDirectory: &isDir), isDir.boolValue {
                let dest = (modsDir as NSString).appendingPathComponent(first)
                try? fm.removeItem(atPath: dest)
                try fm.moveItem(atPath: firstPath, toPath: dest)
                return
            }
        }

        let dest = (modsDir as NSString).appendingPathComponent(mod.id)
        try? fm.removeItem(atPath: dest)
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        for item in visible {
            let src = (tmpExtract as NSString).appendingPathComponent(item)
            let dst = (dest as NSString).appendingPathComponent(item)
            try fm.moveItem(atPath: src, toPath: dst)
        }
    }

    /// Quartz ships its plugin DLL into Mods/ and its data folder into UserData/.
    /// The MelonLoader build (Quartz.zip) is already laid out that way at the
    /// game root; the UMM build (QuartzUmm.zip) is a single mod folder that we
    /// reshape into the same destinations.
    private static func installQuartz(extractDir: String, visible: [String], gameRoot: String) throws {
        let fm = FileManager.default
        let modsDest = (gameRoot as NSString).appendingPathComponent("Mods")
        let userDataDest = (gameRoot as NSString).appendingPathComponent("UserData")
        try? fm.createDirectory(atPath: modsDest, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: userDataDest, withIntermediateDirectories: true)

        let hasGameRootLayout = visible.contains("Mods") || visible.contains("UserData")
        if hasGameRootLayout {
            // MelonLoader build: merge top-level Mods/ and UserData/ into place.
            if visible.contains("Mods") {
                try merge(from: (extractDir as NSString).appendingPathComponent("Mods"), into: modsDest)
            }
            if visible.contains("UserData") {
                try merge(from: (extractDir as NSString).appendingPathComponent("UserData"), into: userDataDest)
            }
            return
        }

        // UMM build: a single mod folder (e.g. "Quartz") — move it whole into Mods/.
        guard let folder = visible.first(where: { name in
            var isDir: ObjCBool = false
            let p = (extractDir as NSString).appendingPathComponent(name)
            return fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
        }) else { throw ModDownloadError.emptyArchive }

        let folderPath = (extractDir as NSString).appendingPathComponent(folder)
        let dest = (modsDest as NSString).appendingPathComponent(folder)
        try? fm.removeItem(atPath: dest)
        try fm.moveItem(atPath: folderPath, toPath: dest)
    }

    /// Moves each top-level child of `src` into `dst`, replacing existing entries.
    private static func merge(from src: String, into dst: String) throws {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        for item in (try? fm.contentsOfDirectory(atPath: src)) ?? [] where !item.hasPrefix(".") {
            let from = (src as NSString).appendingPathComponent(item)
            let to = (dst as NSString).appendingPathComponent(item)
            try? fm.removeItem(atPath: to)
            try fm.moveItem(atPath: from, toPath: to)
        }
    }
}
