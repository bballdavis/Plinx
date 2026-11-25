import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// PlinxContentRules — synchronous content checks against an explicit policy
// ─────────────────────────────────────────────────────────────────────────────
//
// Every provider response is already filtered by `SafeMediaServices` through
// `ContentSafetyGate`. These checks apply the same rules (PlinxCore's rating
// normalizer and `SafetyInterceptor`) to data that did not come through that
// boundary or that must be judged against a specific policy: downloads stored
// on the device, a policy captured when a launch started, parity tests.
//
// All checks fail closed: a missing or unrecognized rating is rejected unless
// the policy allows unrated content, and adult-only ratings are always
// rejected. Collections and playlists are containers; their entries are
// checked one by one when they are opened.
//
// ─────────────────────────────────────────────────────────────────────────────

enum PlinxContentRules {
    // MARK: - Single item checks

    static func isAllowed(_ item: MediaItem, policy: SafetyPolicy) -> Bool {
        isAllowed(id: item.id, title: item.title, contentRating: item.contentRating, policy: policy)
    }

    static func isAllowed(_ displayItem: MediaDisplayItem, policy: SafetyPolicy) -> Bool {
        switch displayItem {
        case let .playable(item):
            isAllowed(item, policy: policy)
        case .collection, .playlist:
            true
        }
    }

    static func isAllowed(_ item: PlayableMediaItem, policy: SafetyPolicy) -> Bool {
        isAllowed(id: item.id, title: item.title, contentRating: item.contentRating, policy: policy)
    }

    /// A raw Plex entry, e.g. a play-queue member checked before autoplay.
    static func isAllowed(_ item: PlexItem, policy: SafetyPolicy) -> Bool {
        isAllowed(id: item.ratingKey, title: item.title, contentRating: item.contentRating, policy: policy)
    }

    // MARK: - Batch filtering

    /// Returns `nil` when no item survives, so the caller drops the hub.
    static func filtered(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        let allowed = filteredItems(hub.items, policy: policy)
        guard !allowed.isEmpty else { return nil }
        return Hub(
            id: hub.id,
            key: hub.key,
            hubKey: hub.hubKey,
            title: hub.title,
            size: allowed.count,
            more: hub.more,
            items: allowed,
            server: hub.server
        )
    }

    static func filteredItems(_ items: [MediaDisplayItem], policy: SafetyPolicy) -> [MediaDisplayItem] {
        items.filter { isAllowed($0, policy: policy) }
    }

    // MARK: - Private

    private static func isAllowed(id: String, title: String, contentRating: String?, policy: SafetyPolicy) -> Bool {
        SafetyInterceptor(policy: policy).isAllowed(
            PlinxMediaItem(id: id, title: title, labels: [], contentRating: contentRating)
        )
    }
}
