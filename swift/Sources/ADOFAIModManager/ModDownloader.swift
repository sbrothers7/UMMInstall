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
    static func install(mod: Mod, into modsDir: String) async throws {
        let tmpZip = "/tmp/adofai_mod_\(mod.id).zip"
        let tmpExtract = "/tmp/adofai_extract_\(mod.id)"
        let fm = FileManager.default

        defer {
            try? fm.removeItem(atPath: tmpZip)
            try? fm.removeItem(atPath: tmpExtract)
        }

        try await Network.downloadFile(from: mod.url, to: tmpZip)

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
}
