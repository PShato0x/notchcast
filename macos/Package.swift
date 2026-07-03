// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchAI",
            path: "Sources/NotchAI"
        )
    ]
)
