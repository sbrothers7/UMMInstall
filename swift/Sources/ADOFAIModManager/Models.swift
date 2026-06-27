import Foundation

enum LogLevel: String {
    case info, ok, error, detail
}

enum Language: String, CaseIterable {
    case en
    case ko
}

enum LoaderType: String, CaseIterable {
    case umm
    case melonLoader
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let level: LogLevel
    let message: String
}

enum InstallPhase: Equatable {
    case updating
    case confirm
    case needsVerify
    case installed
    case picker
    case installingBrew
    case installing
    case uninstalling
    case migrating
    case confirmModMove
    case complete(success: Bool, message: String)
}
