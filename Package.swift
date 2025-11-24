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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Pioneer",
            dependencies: [],
            path: "Sources"
        )
    ]
)

