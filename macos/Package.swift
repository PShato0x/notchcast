// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeIsland",
            path: "Sources/ClaudeIsland"
        )
    ]
)
