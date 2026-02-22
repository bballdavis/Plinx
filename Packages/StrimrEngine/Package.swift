// swift-tools-version: 6.0
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// StrimrEngine — Vendor Wrapper Package
// ─────────────────────────────────────────────────────────────────────────────
//
// This package compiles the upstream Strimr source code (Vendor/Strimr) as an
// independent SPM module. It serves three purposes:
//
//   1. **CI validation** — `swift build` on this package proves the vendor
//      code compiles cleanly after every submodule bump.
//   2. **Dependency documentation** — the Package.swift is the single source
//      of truth for what Strimr needs (MPVKit, platform versions).
//   3. **Future migration** — when Strimr adds `public` access to its API,
//      PlinxCore/PlinxUI can `import StrimrEngine` directly. Until then, the
//      app target compiles vendor sources inline for `internal` access.
//
// Source Strategy:
//   Symlinks under Sources/StrimrEngine/Vendor/ and Sources/StrimrIOSViews/Vendor/
//   point back to the actual Vendor/Strimr/Shared and Vendor/Strimr/Strimr-iOS/Features
//   directories respectively. SPM follows symlinks during source discovery.
//
// Access Control Note:
//   All Strimr types use Swift's default `internal` access. When compiled as a
//   separate module, these types are invisible to external importers. The
//   Exports.swift shim in each target adds `public` protocols + factory functions
//   for the subset of types needed by PlinxCore/PlinxUI. The PlinxApp target
//   continues to compile vendor sources directly for full internal access.
//
// ─────────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "StrimrEngine",
    platforms: [
        .iOS(.v18),
        // macOS minimum satisfies MPVKit's requirement for SPM resolution.
        // Strimr uses UIKit, so macOS builds won't compile — validate via:
        //   swift build --sdk $(xcrun --show-sdk-path --sdk iphonesimulator)
        .macOS(.v14)
    ],
    products: [
        .library(name: "StrimrEngine", targets: ["StrimrEngine"]),
        .library(name: "StrimrIOSViews", targets: ["StrimrIOSViews"])
    ],
    dependencies: [
        // MPVKit — the media playback engine (GPL-licensed).
        // Product name is "MPVKit-GPL" per upstream's Package.swift.
        .package(url: "https://github.com/wunax/MPVKit", exact: "0.41.2")
    ],
    targets: [
        // ── StrimrEngine ────────────────────────────────────────────────
        // Wraps Vendor/Strimr/Shared — models, repositories, networking,
        // view models, player infrastructure, session/store management.
        .target(
            name: "StrimrEngine",
            dependencies: [
                .product(name: "MPVKit-GPL", package: "MPVKit")
            ],
            path: "Sources/StrimrEngine",
            exclude: [
                // VLC player — Plinx uses MPVKit exclusively.
                "Vendor/Shared/Library/VLC"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),

        // ── StrimrIOSViews ──────────────────────────────────────────────
        // Wraps Vendor/Strimr/Strimr-iOS/Features — iOS-specific views
        // (HomeView, LibraryView, PlayerWrapper, etc.).
        // Needed during progressive view replacement; will be removed once
        // all Strimr views are replaced by Plinx equivalents (Phase 6).
        .target(
            name: "StrimrIOSViews",
            dependencies: ["StrimrEngine"],
            path: "Sources/StrimrIOSViews",
            // No excludes needed — symlink targets only Features/ content.
            //
            // Note: If Strimr adds non-Swift resources under Features/,
            // add them to an exclude list here.
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
