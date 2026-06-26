import Foundation

enum Updater {
    static let repo = "sbrothers7/UMMInstall"

    struct LatestRelease {
        let tag: String
        let downloadURL: URL
    }

    enum UpdateError: LocalizedError {
        case notWritable(String)
        case appNotFoundInZip
        case httpError(Int)
        case unzipFailed

        var errorDescription: String? {
            switch self {
            case .notWritable(let path):
                return "Can't write to \(path). Move the app to a writable location (e.g. ~/Applications) and remove quarantine, then retry."
            case .appNotFoundInZip: return ".app not found in update archive."
            case .httpError(let code): return "HTTP \(code)"
            case .unzipFailed: return "Failed to unzip the update."
            }
        }
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
                .map { Int($0.prefix { $0.isNumber }) ?? 0 }
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

    // MARK: - Gatekeeper App Translocation
    //
    // A quarantined app launched via the Gatekeeper bypass (right-click → Open)
    // runs from a randomized, read-only mount under
    // /private/var/folders/.../AppTranslocation/<UUID>/d/…. Bundle.main.bundleURL
    // then points at that read-only copy, so a naive rm/mv self-update silently
    // fails to touch the real on-disk app and the next launch re-translocates the
    // old version — an infinite update loop. Resolve the original path so we
    // replace the file the user actually launches.

    private typealias IsTransFn = @convention(c)
        (CFURL, UnsafeMutablePointer<DarwinBoolean>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
    private typealias OrigPathFn = @convention(c)
        (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    private static let securityHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW)

    /// Returns the de-translocated path for `url`, or `url` unchanged if it isn't
    /// translocated (or the API is unavailable).
    static func resolveOriginalPath(_ url: URL) -> URL {
        guard let handle = securityHandle,
              let isSym = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let origSym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else {
            return url
        }
        let isTranslocated = unsafeBitCast(isSym, to: IsTransFn.self)
        var flag = DarwinBoolean(false)
        guard isTranslocated(url as CFURL, &flag, nil).boolValue, flag.boolValue else {
            return url
        }
        let originalPath = unsafeBitCast(origSym, to: OrigPathFn.self)
        guard let unmanaged = originalPath(url as CFURL, nil) else { return url }
        return unmanaged.takeRetainedValue() as URL
    }

    static func performUpdate(downloadURL: URL) async throws {
        let fm = FileManager.default

        // Resolve the real install location and confirm we can write it BEFORE
        // downloading or quitting — so an un-updatable location falls through to
        // normal launch instead of looping.
        let targetURL = resolveOriginalPath(Bundle.main.bundleURL)
        let targetPath = targetURL.path
        let parentPath = targetURL.deletingLastPathComponent().path
        guard fm.isWritableFile(atPath: parentPath) else {
            throw UpdateError.notWritable(parentPath)
        }

        let tmpZip = "/tmp/adofai-mm-update.zip"
        let tmpDir = "/tmp/adofai-mm-update"
        try? fm.removeItem(atPath: tmpZip)
        try? fm.removeItem(atPath: tmpDir)

        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw UpdateError.httpError(http.statusCode)
        }
        try data.write(to: URL(fileURLWithPath: tmpZip))

        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.launchPath = "/usr/bin/unzip"
        unzip.arguments = ["-q", "-o", tmpZip, "-d", tmpDir]
        try unzip.run()
        unzip.waitUntilExit()
        if unzip.terminationStatus != 0 { throw UpdateError.unzipFailed }

        guard let newApp = try findAppBundle(in: tmpDir) else {
            throw UpdateError.appNotFoundInZip
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = "/tmp/adofai-mm-update.sh"
        let script = """
        #!/bin/bash
        LOG="/tmp/adofai-mm-update.log"
        exec >>"$LOG" 2>&1
        echo "=== update $(date) ==="
        APP="\(targetPath)"
        NEW="\(newApp)"
        PID="\(pid)"
        echo "APP=$APP"
        echo "NEW=$NEW"
        # Wait for the running app to exit (cap ~20s).
        for _ in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        sleep 0.3
        if [ ! -d "$NEW" ]; then echo "ERROR: new app missing at $NEW"; exit 1; fi
        rm -rf "$APP" && echo "removed old" || { echo "ERROR: rm failed"; exit 1; }
        mv "$NEW" "$APP" && echo "moved new into place" || { echo "ERROR: mv failed"; exit 1; }
        # Clear quarantine so the swapped-in app stops translocating on next launch.
        xattr -dr com.apple.quarantine "$APP" 2>/dev/null && echo "quarantine cleared" || echo "no quarantine attr"
        open "$APP" && echo "relaunched" || echo "ERROR: open failed"
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
