// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pioneer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Pioneer",
            targets: ["Pioneer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", from: "0.20.9"),
    ],
    targets: [
        .executableTarget(
            name: "Pioneer",
            dependencies: [
                .product(name: "TreeSitter", package: "tree-sitter"),
            ],
            path: "Sources"
        )
    ]
)

