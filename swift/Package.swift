// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ADOFAIModManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ADOFAIModManager",
            path: "Sources/ADOFAIModManager"
        )
    ]
)
