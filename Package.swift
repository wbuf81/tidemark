// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tidemark",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TidemarkCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Tidemark",
            dependencies: ["TidemarkCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TidemarkCoreTests",
            dependencies: ["TidemarkCore"],
            exclude: ["Calendar/Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
