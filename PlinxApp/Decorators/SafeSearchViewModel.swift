import Foundation
import Observation
import PlinxCore

/// Wraps Strimr's `SearchViewModel` and filters results through `SafetyPolicy`.
@MainActor
@Observable
final class SafeSearchViewModel {
    static let minimumLiveSearchCharacters = 4

    // MARK: - Filtered output
    private(set) var items: [MediaDisplayItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasSearched = false

    /// Forwarded directly to inner — binding to the search field still works.
    var query: String {
        get { inner.query }
        set { inner.query = newValue }
    }

    // MARK: - Private
    private let inner: SearchViewModel
    private var policy: SafetyPolicy
    @ObservationIgnored private var stateSyncTask: Task<Void, Never>?

    init(inner: SearchViewModel, policy: SafetyPolicy = .ratingOnly()) {
        self.inner = inner
        self.policy = policy
    }

    deinit {
        stateSyncTask?.cancel()
    }

    // MARK: - Actions

    func queryDidChange() {
        stateSyncTask?.cancel()

        guard hasQuery else {
            resetSearchState()
            inner.queryDidChange()
            return
        }

        guard trimmedQuery.count >= Self.minimumLiveSearchCharacters else {
            resetSearchState()
            return
        }

        hasSearched = true
        isLoading = true
        errorMessage = nil

        stateSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.inner.submitSearch()
            await self.syncStateFromInnerSearch()
        }
    }

    func submitSearch() {
        stateSyncTask?.cancel()

        guard hasQuery else {
            resetSearchState()
            inner.submitSearch()
            return
        }

        hasSearched = true
        inner.submitSearch()
        stateSyncTask = Task { [weak self] in
            await self?.syncStateFromInnerSearch()
        }
    }

    func clear() {
        stateSyncTask?.cancel()
        inner.query = ""
        inner.queryDidChange()
        resetSearchState()
    }

    /// Updates the safety policy and re-filters any currently displayed results.
    /// Call this when `SafetyPolicy` changes (e.g., user updates settings).
    func updatePolicy(_ newPolicy: SafetyPolicy) {
        guard newPolicy != policy else { return }
        policy = newPolicy
        applyFilters()
    }

    var shouldShowTypingPrompt: Bool {
        hasQuery && !hasSearched && trimmedQuery.count < Self.minimumLiveSearchCharacters
    }

    var remainingCharactersForLiveSearch: Int {
        max(Self.minimumLiveSearchCharacters - trimmedQuery.count, 0)
    }

    // MARK: - Filtering

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasQuery: Bool {
        !trimmedQuery.isEmpty
    }

    private func applyFilters() {
        // Apply Strimr's type filters first, then Plinx safety filter on top.
        items = inner.filteredItems.filter { StrimrAdapter.isAllowed($0, policy: policy) }
        isLoading = inner.isLoading
        errorMessage = inner.errorMessage
    }

    private func resetSearchState() {
        items = []
        isLoading = false
        errorMessage = nil
        hasSearched = false
    }

    private func syncStateFromInnerSearch() async {
        var observedLoading = false

        for _ in 0..<60 {
            guard !Task.isCancelled else { return }

            applyFilters()
            if inner.isLoading {
                observedLoading = true
            } else if observedLoading {
                break
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        applyFilters()
    }
}
