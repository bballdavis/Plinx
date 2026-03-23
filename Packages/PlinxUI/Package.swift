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
//   • PlinxViewFactory — protocol for view resolution (implemented in PlinxApp)
//
// Module Boundary:
//   PlinxUI imports PlinxCore (for HapticManager, PlinkAudioManager, model types).
//   PlinxUI does not import Strimr or any Strimr types.
//   All data arriving at PlinxUI views is pre-adapted by PlinxApp decorators.
//
// ─────────────────────────────────────────────────────────────────────────────

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
        .package(path: "../PlinxCore"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
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
            dependencies: [
                "PlinxUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        )
    ]
)
