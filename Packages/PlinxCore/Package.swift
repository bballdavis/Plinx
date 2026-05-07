// swift-tools-version: 6.0
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// PlinxCore — Safety, Playback Policy, Haptics, Audio, Model Types
// ─────────────────────────────────────────────────────────────────────────────
//
// PlinxCore is the domain layer for Plinx. It owns:
//   • SafetyInterceptor + SafetyPolicy — content filtering (fail-closed)
//   • MathGate — parental gate challenge generator
//   • PlinxRating / PlinxMediaItem — public model types (bridge types)
//   • HapticManager + PlinkAudioManager — tactile feedback
//   • PlaybackCoordinator + PlaybackPolicy — lifecycle management
//   • PlexClient protocol — abstract Plex API surface
//
// Module Boundary:
//   PlinxCore does not import Strimr directly.
//   Instead, PlinxCore defines its own public model types. The PlinxApp target
//   bridges between sibling Strimr source and PlinxCore's public types via
//   adapters and decorators.
//
// ─────────────────────────────────────────────────────────────────────────────

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
        // MPVKit — linked transitively for PlaybackEngine protocol implementations.
        .package(url: "https://github.com/wunax/MPVKit", exact: "0.41.2"),
        // Sentry — crash reporting (evaluate PII before enabling in prod).
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.1.0")
    ],
    targets: [
        .target(
            name: "PlinxCore",
            dependencies: [
                .product(name: "MPVKit-GPL", package: "MPVKit"),
                .product(name: "Sentry", package: "sentry-cocoa")
            ]
        ),
        .testTarget(
            name: "PlinxCoreTests",
            dependencies: ["PlinxCore"]
        )
    ]
)
