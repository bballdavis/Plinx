import Foundation
import Observation
import PlinxCore

/// Wraps Strimr's `HomeViewModel` and post-filters hubs through `SafetyPolicy`
/// so that only age-appropriate content reaches any Plinx view.
@MainActor
@Observable
final class SafeHomeViewModel {
    // MARK: - Filtered output (what views observe)
    private(set) var continueWatching: Hub?
    private(set) var recentlyAdded: [Hub] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Private
    private let inner: HomeViewModel
    private let policy: SafetyPolicy

    init(inner: HomeViewModel, policy: SafetyPolicy = .ratingOnly()) {
        self.inner = inner
        self.policy = policy
    }

    var hasContent: Bool {
        (continueWatching?.hasItems ?? false) || !recentlyAdded.isEmpty
    }

    // MARK: - Actions

    func load() async {
        isLoading = true
        await inner.load()
        applyFilters()
    }

    func reload() async {
        isLoading = true
        await inner.reload()
        applyFilters()
    }

    // MARK: - Filtering

    private func applyFilters() {
        continueWatching = inner.continueWatching.flatMap {
            StrimrAdapter.filtered($0, policy: policy)
        }
        recentlyAdded = inner.recentlyAdded.compactMap {
            StrimrAdapter.filtered($0, policy: policy)
        }
        isLoading = inner.isLoading
        errorMessage = inner.errorMessage
    }
}
