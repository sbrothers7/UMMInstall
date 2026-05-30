import Foundation

private final class LineBuffer {
    var data = Data()
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

final class ScriptRunner {
    func run(scriptPath: String, onLine: @Sendable @escaping (String) -> Void) async -> Int32 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let process = Process()
            process.launchPath = "/usr/bin/script"
            process.arguments = ["-q", "/dev/null", "/bin/zsh", scriptPath]

            // .app processes inherit a minimal PATH that excludes Homebrew's
            // install prefixes — prepend them so the bash sees `brew` and
            // doesn't try to re-install Homebrew via an interactive sudo prompt.
            var env = ProcessInfo.processInfo.environment
            let brewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
            let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = "\(brewPaths):\(existing)"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = LineBuffer()
            let lock = NSLock()
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty { return }
                lock.lock()
                buffer.append(chunk, onLine: onLine)
                lock.unlock()
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil
                lock.lock()
                buffer.drain(onLine)
                lock.unlock()
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }
}
