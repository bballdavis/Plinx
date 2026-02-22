import Foundation
import Observation
import SwiftUI
import PlinxCore

/// Wraps Strimr's `MediaDetailViewModel`.
///
/// If the media item's content rating exceeds the policy maximum, `isBlocked`
/// is set to `true` and all data loading is suppressed — the view shows a
/// "Content not available" screen instead.
@MainActor
@Observable
final class SafeMediaDetailViewModel {
    // MARK: - Safety gate
    private(set) var isBlocked: Bool

    // MARK: - Delegated state
    var media: PlayableMediaItem { inner.media }
    var heroImageURL: URL? { inner.heroImageURL }
    var isLoading: Bool { inner.isLoading }
    var errorMessage: String? { inner.errorMessage }
    var backdropGradient: [Color] { inner.backdropGradient }
    var cast: [CastMember] { inner.cast }
    var selectedSeasonId: String? {
        get { inner.selectedSeasonId }
        set { inner.selectedSeasonId = newValue }
    }
    var onDeckItem: MediaItem? { inner.onDeckItem }
    var isLoadingSeasons: Bool { inner.isLoadingSeasons }
    var isLoadingEpisodes: Bool { inner.isLoadingEpisodes }
    var isLoadingRelatedHubs: Bool { inner.isLoadingRelatedHubs }
    var seasonsErrorMessage: String? { inner.seasonsErrorMessage }
    var episodesErrorMessage: String? { inner.episodesErrorMessage }
    var relatedHubsErrorMessage: String? { inner.relatedHubsErrorMessage }

    // MARK: - Filtered output
    private(set) var seasons: [MediaItem] = []
    private(set) var episodes: [MediaItem] = []
    private(set) var relatedHubs: [Hub] = []

    // MARK: - Private
    private let inner: MediaDetailViewModel
    private let policy: SafetyPolicy

    init(inner: MediaDetailViewModel, policy: SafetyPolicy = .ratingOnly()) {
        self.inner = inner
        self.policy = policy
        // Belt-and-suspenders: block immediately if the media itself is unsafe.
        self.isBlocked = !StrimrAdapter.isAllowed(inner.media, policy: policy)
    }

    // MARK: - Actions

    func loadDetails() async {
        guard !isBlocked else { return }
        await inner.loadDetails()
        applyFilters()
    }

    func loadSeasonsIfNeeded(forceReload: Bool = false) async {
        guard !isBlocked else { return }
        await inner.loadSeasonsIfNeeded(forceReload: forceReload)
        applyFilters()
    }

    func selectSeason(id: String) async {
        guard !isBlocked else { return }
        await inner.selectSeason(id: id)
        filterEpisodes()
    }

    func playbackRatingKey() async -> String? {
        guard !isBlocked else { return nil }
        return await inner.playbackRatingKey()
    }

    // MARK: - Filtering

    private func applyFilters() {
        seasons = inner.seasons  // Season items rarely carry individual ratings.
        filterEpisodes()
        relatedHubs = inner.relatedHubs.compactMap {
            StrimrAdapter.filtered($0, policy: policy)
        }
    }

    private func filterEpisodes() {
        episodes = inner.episodes.filter { StrimrAdapter.isAllowed($0, policy: policy) }
    }
}
