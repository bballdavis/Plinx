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
        .package(url: "https://github.com/wunax/MPVKit", exact: "0.41.2"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.1.0")
    ],
    targets: [
        .target(
            name: "PlinxCore",
            dependencies: [
                .product(name: "MPVKit", package: "MPVKit"),
                .product(name: "Sentry", package: "sentry-cocoa")
            ]
        ),
        .testTarget(
            name: "PlinxCoreTests",
            dependencies: ["PlinxCore"]
        )
    ]
)
