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
//   • HapticManager — tactile feedback
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
        .tvOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlinxCore", targets: ["PlinxCore"])
    ],
    dependencies: [],
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
