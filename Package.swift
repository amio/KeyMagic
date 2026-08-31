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
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", exact: "0.10.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", exact: "0.23.1"),
    ],
    targets: [
        .target(
            name: "TapTickKit",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterRuby", package: "tree-sitter-ruby"),
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
