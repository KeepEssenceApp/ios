// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeepCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KeepCore", targets: ["KeepCore"]),
    ],
    targets: [
        .target(
            name: "KeepCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KeepCoreTests",
            dependencies: ["KeepCore"]
        ),
    ]
)
