// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapIt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SnapIt",
            path: "Sources/SnapIt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
