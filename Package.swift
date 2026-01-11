// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleAccessibilityKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "AppleAccessibilityKit",
            targets: ["AppleAccessibilityKit"]
        ),
    ],
    targets: [
        .target(
            name: "AppleAccessibilityKit",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "AppleAccessibilityKitTests",
            dependencies: ["AppleAccessibilityKit"]
        ),
    ]
)
