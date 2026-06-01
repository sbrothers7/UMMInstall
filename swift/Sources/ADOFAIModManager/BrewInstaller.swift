import Foundation

private final class LineBuffer {
    private var data = Data()
    func append(_ chunk: Data, onLine: (String) -> Void) {
        data.append(chunk)
        while let nl = data.firstIndex(of: 0x0A) {
            let lineData = data.subdata(in: data.startIndex..<nl)
            data.removeSubrange(data.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                onLine(line)
            }
        }
    }
    func drain(_ onLine: (String) -> Void) {
        if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
            onLine(line)
        }
        data.removeAll()
    }
}

enum BrewInstaller {
    enum InstallError: LocalizedError {
        case downloadFailed(String)
        case fifoSetup(String)
        case authCancelled
        case installerExit(Int32, String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let m): return "Failed to download Homebrew installer: \(m)"
            case .fifoSetup(let m):      return "Pipe setup failed: \(m)"
            case .authCancelled:         return "Authorization cancelled."
            case .installerExit(let c, let m):
                return m.isEmpty ? "Homebrew installer exited with code \(c)." : m
            }
        }
    }

    static func install(streamingTo onLine: @Sendable @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        let installerScript = "/tmp/adofai-homebrew-install.sh"
        let helperScript = "/tmp/adofai-brew-helper.sh"
        let fifo = "/tmp/adofai-brew-pipe"
        let user = NSUserName()

        defer {
            try? fm.removeItem(atPath: installerScript)
            try? fm.removeItem(atPath: helperScript)
            unlink(fifo)
        }

        let url = URL(string: "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw InstallError.downloadFailed("HTTP \(http.statusCode)")
        }
        try data.write(to: URL(fileURLWithPath: installerScript))

        // Helper runs as root (via `do shell script with administrator
        // privileges`). It writes a temporary sudoers.d entry granting the
        // calling user passwordless sudo, drops back to that user, runs the
        // Homebrew installer through script(1) so output is line-flushed into
        // the FIFO, and cleans up on any exit path.
        let helper = """
        #!/bin/bash
        set -e
        ORIG_USER="$1"
        INSTALLER="$2"
        FIFO="$3"
        SUDOERS="/etc/sudoers.d/adofai-brew-temp"
        cleanup() { rm -f "$SUDOERS"; }
        trap cleanup EXIT INT TERM HUP
        echo "$ORIG_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS"
        chmod 0440 "$SUDOERS"
        sudo -u "$ORIG_USER" NONINTERACTIVE=1 /usr/bin/script -F -q "$FIFO" /bin/bash "$INSTALLER"
        """
        try helper.write(toFile: helperScript, atomically: true, encoding: .utf8)
        _ = chmod(helperScript, 0o755)

        unlink(fifo)
        if mkfifo(fifo, 0o644) != 0 {
            throw InstallError.fifoSetup("mkfifo errno \(errno)")
        }

        let fd = open(fifo, O_RDONLY | O_NONBLOCK)
        if fd < 0 {
            throw InstallError.fifoSetup("open errno \(errno)")
        }
        let readHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let buffer = LineBuffer()
        let lock = NSLock()
        readHandle.readabilityHandler = { fh in
            let chunk = fh.availableData
            if chunk.isEmpty { return }
            lock.lock()
            buffer.append(chunk, onLine: onLine)
            lock.unlock()
        }

        let appleScript = """
        do shell script "/bin/bash '\(helperScript)' '\(user)' '\(installerScript)' '\(fifo)'" with administrator privileges
        """

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = Pipe()
        try task.run()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                task.waitUntilExit()
                cont.resume()
            }
        }

        readHandle.readabilityHandler = nil
        lock.lock()
        buffer.drain(onLine)
        lock.unlock()
        try? readHandle.close()

        let exit = task.terminationStatus
        if exit != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? ""
            if err.contains("User canceled") || err.contains("-128") {
                throw InstallError.authCancelled
            }
            throw InstallError.installerExit(exit, err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
