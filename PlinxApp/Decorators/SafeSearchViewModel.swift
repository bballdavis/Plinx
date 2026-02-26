import Foundation
import Observation
import PlinxCore

/// Wraps Strimr's `SearchViewModel` and filters results through `SafetyPolicy`.
@MainActor
@Observable
final class SafeSearchViewModel {
    // MARK: - Filtered output
    private(set) var items: [MediaDisplayItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Forwarded directly to inner — binding to the search field still works.
    var query: String {
        get { inner.query }
        set { inner.query = newValue }
    }

    // MARK: - Private
    private let inner: SearchViewModel
    private var policy: SafetyPolicy

    init(inner: SearchViewModel, policy: SafetyPolicy = .ratingOnly()) {
        self.inner = inner
        self.policy = policy
    }

    // MARK: - Actions

    func queryDidChange() {
        inner.queryDidChange()
        applyFilters()
    }

    func submitSearch() {
        inner.submitSearch()
        applyFilters()
    }

    func clear() {
        inner.query = ""
        inner.submitSearch()
        items = []
        errorMessage = nil
    }

    /// Updates the safety policy and re-filters any currently displayed results.
    /// Call this when `SafetyPolicy` changes (e.g., user updates settings).
    func updatePolicy(_ newPolicy: SafetyPolicy) {
        guard newPolicy != policy else { return }
        policy = newPolicy
        applyFilters()
    }

    // MARK: - Filtering

    private func applyFilters() {
        // Apply Strimr's type filters first, then Plinx safety filter on top.
        items = inner.filteredItems.filter { StrimrAdapter.isAllowed($0, policy: policy) }
        isLoading = inner.isLoading
        errorMessage = inner.errorMessage
    }
}
