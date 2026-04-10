// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlinxTestSupport",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlinxTestSupport", targets: ["PlinxTestSupport"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PlinxTestSupport",
            dependencies: [],
            path: "Sources"
        )
    ]
)
