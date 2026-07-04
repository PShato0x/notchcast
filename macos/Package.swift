// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchCast",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchCast",
            path: "Sources/NotchCast"
        )
    ]
)
