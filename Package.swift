// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapTikKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "TapTikKit", targets: ["TapTikKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "TapTikKit",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/TapTikKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "TapTikTests",
            dependencies: ["TapTikKit"],
            path: "Tests/TapTikTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)