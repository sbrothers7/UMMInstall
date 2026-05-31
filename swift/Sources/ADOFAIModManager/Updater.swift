import Foundation

enum Updater {
    static let repo = "sbrothers7/UMMInstall"

    struct LatestRelease {
        let tag: String
        let downloadURL: URL
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func fetchLatest() async throws -> LatestRelease {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            throw NSError(domain: "Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: "malformed release JSON"])
        }
        let asset = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }
        guard let urlStr = asset?["browser_download_url"] as? String,
              let downloadURL = URL(string: urlStr) else {
            throw NSError(domain: "Updater", code: 2, userInfo: [NSLocalizedDescriptionKey: "no .zip asset on latest release"])
        }
        return LatestRelease(tag: tag, downloadURL: downloadURL)
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
                .split(separator: ".")
                .map { Int($0) ?? 0 }
        }
        let r = parts(remote), l = parts(local)
        let n = max(r.count, l.count)
        for i in 0..<n {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func performUpdate(downloadURL: URL) async throws {
        let fm = FileManager.default
        let tmpZip = "/tmp/adofai-mm-update.zip"
        let tmpDir = "/tmp/adofai-mm-update"
        try? fm.removeItem(atPath: tmpZip)
        try? fm.removeItem(atPath: tmpDir)

        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "Updater", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        try data.write(to: URL(fileURLWithPath: tmpZip))

        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.launchPath = "/usr/bin/unzip"
        unzip.arguments = ["-q", "-o", tmpZip, "-d", tmpDir]
        try unzip.run()
        unzip.waitUntilExit()
        if unzip.terminationStatus != 0 {
            throw NSError(domain: "Updater", code: 10, userInfo: [NSLocalizedDescriptionKey: "unzip failed"])
        }

        guard let newApp = try findAppBundle(in: tmpDir) else {
            throw NSError(domain: "Updater", code: 11, userInfo: [NSLocalizedDescriptionKey: ".app not found in update zip"])
        }

        let currentApp = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = "/tmp/adofai-mm-update.sh"
        let script = """
        #!/bin/bash
        set -e
        APP="\(currentApp)"
        NEW="\(newApp)"
        PID="\(pid)"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        rm -rf "$APP"
        mv "$NEW" "$APP"
        xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
        open "$APP"
        rm -f "\(tmpZip)"
        rm -rf "\(tmpDir)"
        rm -f "$0"
        """
        try script.write(toFile: helper, atomically: true, encoding: .utf8)
        _ = chmod(helper, 0o755)

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [helper]
        let devNullR = FileHandle(forReadingAtPath: "/dev/null")
        let devNullW = FileHandle(forWritingAtPath: "/dev/null")
        task.standardInput = devNullR as Any
        task.standardOutput = devNullW as Any
        task.standardError = devNullW as Any
        try task.run()
    }

    private static func findAppBundle(in dir: String) throws -> String? {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(atPath: dir)
        if let direct = items.first(where: { $0.hasSuffix(".app") }) {
            return (dir as NSString).appendingPathComponent(direct)
        }
        for item in items {
            let sub = (dir as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue {
                if let nested = try findAppBundle(in: sub) { return nested }
            }
        }
        return nil
    }
}
