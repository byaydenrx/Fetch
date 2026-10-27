// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Fetch",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Fetch",
            path: "Sources/Fetch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
