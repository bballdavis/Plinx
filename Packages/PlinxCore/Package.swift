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
//   • ContentRatingNormalizer — raw Plex/Jellyfin rating text → PlinxRating
//   • HapticManager — tactile feedback
//   • PlaybackCoordinator + PlaybackPolicy — lifecycle management
//
// Module Boundary:
//   PlinxCore does not import the app's media stack.
//   Instead, PlinxCore defines its own public model types. The PlinxApp target
//   maps provider items into them at one boundary: `ContentSafetyGate`, which
//   `SafeMediaServices` applies to every provider service.
//
// ─────────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "PlinxCore",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
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
