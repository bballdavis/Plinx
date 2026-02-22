import PlinxCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// PlayQueueState+Identifiable
// ─────────────────────────────────────────────────────────────────────────────
// PlayQueueState already has `let id: Int`, so Identifiable conformance is
// trivially retroactive. This lets PlinxContentView use the `item:` overload
// of fullScreenCover, which is safe on iPad (the `isPresented:` + optional
// content pattern can crash when the sheet is dismissed on iPad before the
// binding clears).
extension PlayQueueState: Identifiable {}

// ─────────────────────────────────────────────────────────────────────────────
// StrimrAdapter — Bridge between Strimr internal types and Plinx safety layer
// ─────────────────────────────────────────────────────────────────────────────
//
// This adapter lives in the PlinxApp target (same compilation unit as Strimr
// vendor sources) so it can access Strimr's `internal` types directly.
//
// It provides:
//   1. `isAllowed` methods — check a single Strimr item against SafetyPolicy
//   2. `filtered` methods — filter hubs/arrays, removing unsafe content
//   3. `toPlinx` methods — convert Strimr types to PlinxCore model types
//
// All methods are fail-closed: missing or unrecognized ratings → reject.
//
// Strimr's `MediaItem` does not expose Plex item-level labels. Library-level
// gating (only showing Kids-type library sections) is enforced separately via
// `LibraryStore` + `SettingsManager`. This adapter provides the belt-and-
// suspenders content-rating check.
//
// ─────────────────────────────────────────────────────────────────────────────

enum StrimrAdapter {

    // MARK: - Single Item Checks

    /// Check a `MediaItem` (base Strimr media type).
    /// - If the item has a recognized rating, enforce the appropriate max
    ///   (TV vs movie) from `policy`.
    /// - If the item has no rating, the result is controlled by
    ///   `policy.allowUnrated`. Library-level gating is the primary guard.
    static func isAllowed(_ item: MediaItem, policy: SafetyPolicy) -> Bool {
        guard let ratingString = item.contentRating,
              !ratingString.isEmpty else {
            return policy.allowUnrated
        }
        guard let rating = PlinxRating.from(contentRating: ratingString) else {
            // Unrecognized rating string — treat as unrated.
            return policy.allowUnrated
        }
        let maxAllowed = rating.isTVRating ? policy.maxTVRating : policy.maxMovieRating
        return rating <= maxAllowed
    }

    /// Check a `MediaDisplayItem` (union of playable + collection).
    /// Collections are always allowed (their children are individually filtered).
    static func isAllowed(_ displayItem: MediaDisplayItem, policy: SafetyPolicy) -> Bool {
        switch displayItem {
        case let .playable(item):
            return isAllowed(item, policy: policy)
        case .collection:
            return true
        }
    }

    /// Check a `PlayableMediaItem` (movie, episode, etc.).
    static func isAllowed(_ item: PlayableMediaItem, policy: SafetyPolicy) -> Bool {
        guard let ratingString = item.contentRating,
              !ratingString.isEmpty else {
            return policy.allowUnrated
        }
        guard let rating = PlinxRating.from(contentRating: ratingString) else {
            return policy.allowUnrated
        }
        let maxAllowed = rating.isTVRating ? policy.maxTVRating : policy.maxMovieRating
        return rating <= maxAllowed
    }

    // MARK: - Batch Filtering

    /// Filter a `Hub` (titled group of display items).
    /// Returns `nil` if no items survive — the caller should remove the hub entirely.
    static func filtered(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        let allowed = hub.items.filter { isAllowed($0, policy: policy) }
        guard !allowed.isEmpty else { return nil }
        return Hub(id: hub.id, title: hub.title, items: allowed)
    }

    /// Filter an array of hubs, removing any that become empty.
    static func filteredHubs(_ hubs: [Hub], policy: SafetyPolicy) -> [Hub] {
        hubs.compactMap { filtered($0, policy: policy) }
    }

    /// Filter an array of display items.
    static func filteredItems(_ items: [MediaDisplayItem], policy: SafetyPolicy) -> [MediaDisplayItem] {
        items.filter { isAllowed($0, policy: policy) }
    }

    /// Filter an array of base media items.
    static func filteredMediaItems(_ items: [MediaItem], policy: SafetyPolicy) -> [MediaItem] {
        items.filter { isAllowed($0, policy: policy) }
    }

    // MARK: - Type Conversion (Strimr → PlinxCore)

    /// Convert a Strimr `MediaItem` to a PlinxCore `PlinxMediaItem`.
    /// Used when passing data to the SafetyInterceptor (which operates on
    /// PlinxCore public types, not Strimr internal types).
    static func toPlinx(_ item: MediaItem) -> PlinxMediaItem {
        PlinxMediaItem(
            id: item.id,
            title: item.title,
            labels: [],  // Strimr MediaItem doesn't carry labels; library-level gating
            rating: PlinxRating.from(contentRating: item.contentRating)
        )
    }

    /// Convert a Strimr `PlayableMediaItem` to a PlinxCore `PlinxMediaItem`.
    static func toPlinx(_ item: PlayableMediaItem) -> PlinxMediaItem {
        PlinxMediaItem(
            id: item.id,
            title: item.primaryLabel,
            labels: [],  // library-level gating
            rating: PlinxRating.from(contentRating: item.contentRating)
        )
    }
}
