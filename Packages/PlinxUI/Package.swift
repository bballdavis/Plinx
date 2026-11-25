// swift-tools-version: 6.0
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// PlinxUI — Liquid Glass Theme Engine, Views, Navigation
// ─────────────────────────────────────────────────────────────────────────────
//
// PlinxUI is the presentation layer for Plinx. It owns:
//   • PlinxTheme + Liquid Glass modifiers — refractive depth visual language
//   • LiquidGlassButton — tactile "Plink" feedback button
//   • BabyLockOverlay — touch-absorbing parental protection
//   • PlinxieLoadingView — mascot loading animation
//   • PlinxMediaCard / PlinxErrorView — reusable view components
//
// Module Boundary:
//   PlinxUI imports PlinxCore (for HapticManager and model types).
//   PlinxUI does not import the app's media stack (PlinxApp/Core).
//   Content reaches PlinxUI views only after the app's safety boundary
//   (SafeMediaServices in PlinxApp/Core/Safety) has filtered it.
//
// ─────────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "PlinxUI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlinxUI", targets: ["PlinxUI"])
    ],
    dependencies: [
        .package(path: "../PlinxCore"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7"),
    ],
    targets: [
        .target(
            name: "PlinxUI",
            dependencies: [
                .product(name: "PlinxCore", package: "PlinxCore")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PlinxUITests",
            dependencies: [
                "PlinxUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: [
                "Snapshots/__Snapshots__",
                "__Snapshots__"
            ]
        )
    ]
)
