// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyMagicKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "KeyMagicKit", targets: ["KeyMagicKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "KeyMagicKit",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/KeyMagicKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "KeyMagicTests",
            dependencies: ["KeyMagicKit"],
            path: "Tests/KeyMagicTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)