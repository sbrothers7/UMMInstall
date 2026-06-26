import Foundation
import AppKit

// Sets the per-user Steam Launch Options for ADOFAI (appid 977950) so the
// MelonLoader setup_helper.sh wrapper runs. Steam stores this in each account's
// userdata/<id>/config/localconfig.vdf. We do a targeted edit (and back the file
// up first) rather than a full re-serialize, so the rest of the file is
// preserved byte-for-byte.
enum SteamConfig {
    static let appID = "977950"

    enum Outcome {
        case updated(count: Int, steamRunning: Bool)
        case noConfigFound
        case failed(String)
    }

    static var isSteamRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.valvesoftware.steam"
        }
    }

    static func localConfigPaths() -> [String] {
        let root = ("~/Library/Application Support/Steam/userdata" as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard let ids = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        return ids
            .map { root + "/" + $0 + "/config/localconfig.vdf" }
            .filter { fm.fileExists(atPath: $0) }
    }

    @discardableResult
    static func setLaunchOptions(setupHelperPath: String) -> Outcome {
        let paths = localConfigPaths()
        if paths.isEmpty { return .noConfigFound }

        // VDF value, with embedded quotes escaped: "<path>/setup_helper.sh" %command%
        let raw = "\"\(setupHelperPath)\" %command%"
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var updated = 0
        for path in paths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            guard let newText = apply(to: text, escapedValue: escaped) else { continue }
            if newText == text { updated += 1; continue }
            let backup = path + ".adofai.bak"
            try? FileManager.default.removeItem(atPath: backup)
            try? FileManager.default.copyItem(atPath: path, toPath: backup)
            do {
                try newText.write(toFile: path, atomically: true, encoding: .utf8)
                updated += 1
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        return updated > 0 ? .updated(count: updated, steamRunning: isSteamRunning) : .noConfigFound
    }

    /// Clears the launch options we set (only if they still reference
    /// setup_helper.sh, so a user's own custom option is left alone).
    @discardableResult
    static func clearLaunchOptions() -> Outcome {
        let paths = localConfigPaths()
        if paths.isEmpty { return .noConfigFound }

        var updated = 0
        for path in paths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            guard let newText = clear(in: text), newText != text else { continue }
            let backup = path + ".adofai.bak"
            try? FileManager.default.removeItem(atPath: backup)
            try? FileManager.default.copyItem(atPath: path, toPath: backup)
            do {
                try newText.write(toFile: path, atomically: true, encoding: .utf8)
                updated += 1
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        return .updated(count: updated, steamRunning: isSteamRunning)
    }

    // MARK: - Targeted VDF edit

    /// Returns text with our LaunchOptions value blanked, or nil if there's
    /// nothing of ours to clear.
    private static func clear(in text: String) -> String? {
        var chars = Array(text)
        guard let apps = blockRange(in: chars, key: "apps", within: 0..<chars.count),
              let block = blockRange(in: chars, key: appID, within: apps),
              let valueRange = launchOptionsValueRange(in: chars, blockBody: block) else {
            return nil
        }
        guard String(chars[valueRange]).contains("setup_helper.sh") else { return nil }
        chars.replaceSubrange(valueRange, with: Array("\"\""))
        return String(chars)
    }

    /// Returns the edited text, or nil if the structure couldn't be located.
    private static func apply(to text: String, escapedValue: String) -> String? {
        var chars = Array(text)

        // The relevant 977950 block lives inside Steam's "apps" block; scope the
        // search there so an unrelated "977950" block elsewhere can't match.
        guard let apps = blockRange(in: chars, key: "apps", within: 0..<chars.count) else {
            return nil
        }

        if let block = blockRange(in: chars, key: appID, within: apps) {
            // 977950 block exists — set or insert its LaunchOptions.
            if let valueRange = launchOptionsValueRange(in: chars, blockBody: block) {
                chars.replaceSubrange(valueRange, with: Array("\"\(escapedValue)\""))
                return String(chars)
            }
            let insertion = Array("\n\t\t\t\t\t\"LaunchOptions\"\t\t\"\(escapedValue)\"")
            chars.insert(contentsOf: insertion, at: block.lowerBound)
            return String(chars)
        }

        // No 977950 block — insert one at the start of the "apps" block.
        let insertion = Array(
            "\n\t\t\t\t\"\(appID)\"\n\t\t\t\t{\n\t\t\t\t\t\"LaunchOptions\"\t\t\"\(escapedValue)\"\n\t\t\t\t}")
        chars.insert(contentsOf: insertion, at: apps.lowerBound)
        return String(chars)
    }

    /// Finds a `"key"` (case-insensitive) within `range` that is followed by a
    /// `{ … }` block, returning the range of the block body (just after `{` up to
    /// the matching `}`). The key appears many times in localconfig.vdf (key/value
    /// pairs, hex blobs); only some are blocks, so scan every occurrence.
    private static func blockRange(in chars: [Character], key: String, within range: Range<Int>) -> Range<Int>? {
        let needle = Array("\"\(key)\"").map { Character($0.lowercased()) }
        let n = needle.count
        guard range.count >= n else { return nil }
        var i = range.lowerBound
        while i <= range.upperBound - n {
            guard chars[i] == "\"" else { i += 1; continue }
            var k = 0
            while k < n, Character(chars[i + k].lowercased()) == needle[k] { k += 1 }
            if k != n { i += 1; continue }

            // After the key, the next non-whitespace char must be `{`.
            var j = i + n
            while j < chars.count, chars[j] == " " || chars[j] == "\t" || chars[j] == "\n" || chars[j] == "\r" {
                j += 1
            }
            if j < chars.count, chars[j] == "{", let body = matchBraces(chars, openBrace: j) {
                return body
            }
            i += 1
        }
        return nil
    }

    /// Given the index of `{`, returns the body range (after `{` to its match `}`).
    private static func matchBraces(_ chars: [Character], openBrace: Int) -> Range<Int>? {
        let bodyStart = openBrace + 1
        var depth = 1
        var j = bodyStart
        while j < chars.count {
            let c = chars[j]
            if c == "\"" { j = skipQuoted(chars, from: j); continue }
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return bodyStart..<j }
            }
            j += 1
        }
        return nil
    }

    /// Within `blockBody`, finds `"LaunchOptions"` (case-insensitive) and returns
    /// the range of its value token, including surrounding quotes.
    private static func launchOptionsValueRange(in chars: [Character], blockBody: Range<Int>) -> Range<Int>? {
        let needle = Array("\"launchoptions\"")
        let n = needle.count
        var i = blockBody.lowerBound
        while i <= blockBody.upperBound - n {
            if chars[i] == "\"" {
                var k = 0
                while k < n, Character(chars[i + k].lowercased()) == needle[k] { k += 1 }
                if k == n {
                    // Skip whitespace to the value's opening quote.
                    var v = i + n
                    while v < blockBody.upperBound,
                          chars[v] == " " || chars[v] == "\t" { v += 1 }
                    guard v < blockBody.upperBound, chars[v] == "\"" else { return nil }
                    let end = skipQuoted(chars, from: v) // index just past closing quote
                    return v..<end
                }
            }
            i += 1
        }
        return nil
    }

    /// Given index of an opening `"`, returns the index just past the closing
    /// `"`, honoring `\"` escapes.
    private static func skipQuoted(_ chars: [Character], from openQuote: Int) -> Int {
        var i = openQuote + 1
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "\"" { return i + 1 }
            i += 1
        }
        return i
    }
}
