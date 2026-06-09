// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spotlight-index",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "spotlight-index", targets: ["spotlight-index"]),
        .library(name: "SpotlightIndexCore", targets: ["SpotlightIndexCore"])
    ],
    targets: [
        .target(name: "SpotlightIndexCore"),
        .executableTarget(
            name: "spotlight-index",
            dependencies: ["SpotlightIndexCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "SpotlightIndexCoreTests",
            dependencies: ["SpotlightIndexCore"]
        )
    ]
)
