import PlinxCore

/// Bridges Strimr's internal domain types to PlinxCore types for safety filtering.
///
/// All methods use `SafetyPolicy.ratingOnly()` by default because Strimr's
/// `MediaItem` does not expose Plex item-level labels. Library-level gating
/// (only showing Kids-type library sections) is enforced separately via
/// `LibraryStore` + `SettingsManager`. This adapter provides the belt-and-
/// suspenders content-rating check.
///
/// This file lives in PlinxApp (not PlinxCore) because Strimr types are
/// `internal` — they compile into the same module as this adapter.
enum StrimrAdapter {

    // MARK: - MediaItem

    static func isAllowed(_ item: MediaItem, policy: SafetyPolicy) -> Bool {
        // Fail-closed: absent or unrecognised rating → reject.
        guard let ratingString = item.contentRating,
              let rating = PlinxRating(rawValue: ratingString) else {
            return false
        }
        return rating <= policy.maxRating
    }

    // MARK: - MediaDisplayItem

    static func isAllowed(_ displayItem: MediaDisplayItem, policy: SafetyPolicy) -> Bool {
        switch displayItem {
        case let .playable(item):
            return isAllowed(item, policy: policy)
        case .collection:
            // Collections themselves have no rating; items inside them are
            // filtered when the collection is loaded.
            return true
        }
    }

    // MARK: - PlayableMediaItem

    static func isAllowed(_ item: PlayableMediaItem, policy: SafetyPolicy) -> Bool {
        guard let ratingString = item.contentRating,
              let rating = PlinxRating(rawValue: ratingString) else {
            return false
        }
        return rating <= policy.maxRating
    }

    // MARK: - Hub helpers

    /// Returns a new Hub containing only allowed display items, or `nil` if empty.
    static func filtered(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        let allowed = hub.items.filter { isAllowed($0, policy: policy) }
        guard !allowed.isEmpty else { return nil }
        return Hub(id: hub.id, title: hub.title, items: allowed)
    }
}
