// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlinxUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlinxUI", targets: ["PlinxUI"])
    ],
    dependencies: [
        .package(path: "../PlinxCore")
    ],
    targets: [
        .target(
            name: "PlinxUI",
            dependencies: [
                .product(name: "PlinxCore", package: "PlinxCore")
            ]
        ),
        .testTarget(
            name: "PlinxUITests",
            dependencies: ["PlinxUI"]
        )
    ]
)
