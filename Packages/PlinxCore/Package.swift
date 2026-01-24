// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlinxCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlinxCore", targets: ["PlinxCore"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "PlinxCore",
            dependencies: []
        ),
        .testTarget(
            name: "PlinxCoreTests",
            dependencies: ["PlinxCore"]
        )
    ]
)
