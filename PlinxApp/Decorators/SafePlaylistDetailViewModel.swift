import Foundation
import Observation
import PlinxCore

enum SafePlaylistPlaybackSelection {
    static func authorizedItems(
        from items: [MediaDisplayItem],
        policy: SafetyPolicy
    ) -> [MediaItem] {
        PlinxContentAuthorization.filteredItems(items, policy: policy).compactMap(\.playableItem)
    }

    static func item(
        from items: [MediaDisplayItem],
        policy: SafetyPolicy,
        shuffled: Bool
    ) -> MediaItem? {
        let playable = authorizedItems(from: items, policy: policy)
        return shuffled ? playable.randomElement() : playable.first
    }
}

@MainActor
@Observable
final class SafePlaylistDetailViewModel {
    var items: [MediaDisplayItem] { inner.items }
    var isLoading: Bool { inner.isLoading }
    var errorMessage: String? { inner.errorMessage }
    var playlist: PlaylistMediaItem { inner.playlist }
    var rawViewModel: PlaylistDetailViewModel { inner }

    private let inner: PlaylistDetailViewModel
    private(set) var policy: SafetyPolicy

    init(inner: PlaylistDetailViewModel, policy: SafetyPolicy) {
        self.inner = inner
        self.policy = policy
        inner.itemFilter = {
            PlinxContentAuthorization.isAllowed($0, policy: policy)
        }
    }

    func load() async {
        await inner.load()
        applyFilters()
    }

    func updatePolicy(_ newPolicy: SafetyPolicy) {
        guard newPolicy != policy else { return }
        policy = newPolicy
        applyFilters()
    }

    func playbackItem(shuffled: Bool) -> MediaItem? {
        SafePlaylistPlaybackSelection.item(
            from: items,
            policy: policy,
            shuffled: shuffled
        )
    }

    private func applyFilters() {
        inner.itemFilter = {
            PlinxContentAuthorization.isAllowed($0, policy: self.policy)
        }
    }
}
