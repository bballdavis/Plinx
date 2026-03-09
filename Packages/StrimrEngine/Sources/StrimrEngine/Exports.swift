// ─────────────────────────────────────────────────────────────────────────────
// StrimrEngine/Exports.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// This file lives in the StrimrEngine module alongside Strimr code (via symlink).
// It serves as the PUBLIC API surface for types that PlinxCore, PlinxUI, and
// PlinxApp need when importing StrimrEngine as a module.
//
// ═══════════════════════════════════════════════════════════════════════════════
// CURRENT STATUS: Strimr types are `internal`. This file defines public
// protocols that mirror key Strimr interfaces. The Strimr types are extended
// to conform to these protocols (in-module, so internal access works).
//
// FUTURE: When Strimr adds `public` access upstream, these protocols become
// unnecessary — consumers can use concrete types directly. Remove the protocols
// and conformance extensions at that point.
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import SwiftUI
import Observation

// MARK: - Type Re-export Manifest
//
// Below is every Strimr type that Plinx code references, grouped by layer.
// Each needs `public` access for full module isolation. Until then, the
// PlinxApp target compiles Strimr sources directly for `internal` access, and
// the `StrimrAdapter` in PlinxApp bridges to PlinxCore's public model types.
//
// ┌─────────────────────────────────────────────────────────┐
// │ Services (Observation/@Observable)                      │
// ├─────────────────────────────────────────────────────────┤
// │ PlexAPIContext         — API client & auth state        │
// │ SessionManager         — sign-in flow state machine     │
// │ SettingsManager        — user preferences               │
// │ LibraryStore           — library metadata cache          │
// │ MainCoordinator        — navigation state               │
// ├─────────────────────────────────────────────────────────┤
// │ View Models                                             │
// ├─────────────────────────────────────────────────────────┤
// │ HomeViewModel          — home screen hubs               │
// │ LibraryViewModel       — library list                   │
// │ SearchViewModel        — search results                 │
// │ MediaDetailViewModel   — media detail + seasons         │
// │ CollectionDetailVM     — collection items               │
// │ PlayerViewModel        — playback state                 │
// │ SignInViewModel         — auth flow                     │
// │ ProfileSwitcherVM      — profile selection              │
// │ ServerSelectionVM      — server picker                  │
// ├─────────────────────────────────────────────────────────┤
// │ Models (value types)                                    │
// ├─────────────────────────────────────────────────────────┤
// │ Hub                    — content hub (carousel)          │
// │ MediaItem              — base media metadata            │
// │ MediaDisplayItem       — display-ready union type       │
// │ PlayableMediaItem      — playable media metadata        │
// │ CollectionMediaItem    — collection metadata            │
// │ PlayQueueState         — play queue snapshot            │
// │ CastMember             — actor/director info            │
// │ Library                — Plex library descriptor        │
// │ PlexItemType           — movie/show/episode enum        │
// │ AppSettings            — serialized settings            │
// ├─────────────────────────────────────────────────────────┤
// │ Player Infrastructure                                   │
// ├─────────────────────────────────────────────────────────┤
// │ PlayerCoordinating     — player protocol (already public│
// │                          in some builds)                 │
// │ PlayerOptions          — playback configuration         │
// │ PlayerTrack            — audio/subtitle track           │
// │ PlayerProperty         — observable player property     │
// │ PlaybackLauncher       — launch-to-play helper          │
// ├─────────────────────────────────────────────────────────┤
// │ Views (SwiftUI)                                         │
// ├─────────────────────────────────────────────────────────┤
// │ MediaImageView         — async image loader             │
// │ MediaImageViewModel    — image loading state            │
// │ PlayerWrapper          — MPV player container           │
// └─────────────────────────────────────────────────────────┘
//
// Migration checklist: when Strimr types become `public`, delete this file
// and update PlinxCore/PlinxUI to `import StrimrEngine` directly.

// MARK: - Module-level re-export marker
// This empty enum exists solely so `import StrimrEngine` compiles even when
// no public symbols are available from vendor code. It also serves as a
// version breadcrumb for the wrapper layer.

public enum StrimrEngineExports {
    /// Wrapper layer version. Bump when Exports.swift changes materially.
    public static let version = "0.1.0"

    /// Set to `true` once Strimr types have `public` access and direct
    /// import is viable. When true, PlinxApp should switch from direct
    /// source compilation to `import StrimrEngine`.
    public static let supportsDirectImport = false
}
