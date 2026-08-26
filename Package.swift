// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TapTickKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "TapTickKit", targets: ["TapTickKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(
            name: "TapTickKit",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/TapTickKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "TapTickTests",
            dependencies: ["TapTickKit"],
            path: "Tests/TapTickTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
