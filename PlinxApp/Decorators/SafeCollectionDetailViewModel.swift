import Foundation
import Observation
import PlinxCore

/// Wraps Strimr's `CollectionDetailViewModel` and filters items through `SafetyPolicy`.
@MainActor
@Observable
final class SafeCollectionDetailViewModel {
    // MARK: - Filtered output
    private(set) var items: [MediaDisplayItem] = []
    var isLoading: Bool { inner.isLoading }
    var errorMessage: String? { inner.errorMessage }
    var collection: CollectionMediaItem { inner.collection }
    var elementsCountText: String? { inner.elementsCountText }
    var yearsText: String? { inner.yearsText }

    // MARK: - Private
    private let inner: CollectionDetailViewModel
    private let policy: SafetyPolicy

    init(inner: CollectionDetailViewModel, policy: SafetyPolicy = .ratingOnly()) {
        self.inner = inner
        self.policy = policy
    }

    // MARK: - Actions

    func load() async {
        await inner.load()
        applyFilters()
    }

    // MARK: - Filtering

    private func applyFilters() {
        items = inner.items.filter { StrimrAdapter.isAllowed($0, policy: policy) }
    }
}
