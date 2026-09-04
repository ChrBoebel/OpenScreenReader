// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenScreenReader",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenScreenReaderCore",
            targets: ["OpenScreenReaderCore"]
        ),
        .executable(
            name: "OpenScreenReaderCoreBehaviorChecks",
            targets: ["OpenScreenReaderCoreBehaviorChecks"]
        ),
    ],
    targets: [
        .target(
            name: "OpenScreenReaderCore"
        ),
        .executableTarget(
            name: "OpenScreenReaderCoreBehaviorChecks",
            dependencies: ["OpenScreenReaderCore"]
        ),
        .testTarget(
            name: "OpenScreenReaderCoreTests",
            dependencies: ["OpenScreenReaderCore"]
        ),
    ]
)
