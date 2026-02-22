import Foundation
import Observation
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// SafeHomeViewModel — Decorator for Strimr's HomeViewModel
// ─────────────────────────────────────────────────────────────────────────────
//
// Pattern: Decorator (GoF)
//
// This class wraps Strimr's `HomeViewModel` (internal, compiled into app module)
// and post-filters ALL hub data through `StrimrAdapter` + `SafetyPolicy` before
// any Plinx view can observe it.
//
// Data Flow:
//   HomeViewModel.load()  →  inner.continueWatching / inner.recentlyAdded
//                          ↓
//   StrimrAdapter.filtered(hub, policy)  →  reject items exceeding maxRating
//                          ↓
//   SafeHomeViewModel.continueWatching / .recentlyAdded  →  PlinxHomeView
//
// Safety guarantee: if a content item has no rating or an unrecognized rating
// string, it is REJECTED (fail-closed via StrimrAdapter).
//
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class SafeHomeViewModel {

    // MARK: - Filtered output (what views observe)

    /// Continue-watching hub, filtered to kid-safe content only.
    /// `nil` if the hub is empty after filtering or hasn't loaded yet.
    private(set) var continueWatching: Hub?

    /// Recently-added hubs, each individually filtered. Empty hubs are removed.
    private(set) var recentlyAdded: [Hub] = []

    /// `true` while the inner view model is fetching data.
    private(set) var isLoading = false

    /// Error message from the inner view model, if any.
    private(set) var errorMessage: String?

    // MARK: - Private

    /// The wrapped Strimr view model. Accesses Plex API via `PlexAPIContext`.
    private let inner: HomeViewModel

    /// The safety policy governing content filtering. Immutable per session —
    /// changes to policy require re-creating the decorator.
    private let policy: SafetyPolicy

    // MARK: - Init

    /// - Parameters:
    ///   - inner: The Strimr `HomeViewModel` to decorate.
    ///   - policy: Safety policy. Defaults to `.ratingOnly()` (no label gate,
    ///     max rating = G).
    init(inner: HomeViewModel, policy: SafetyPolicy = .ratingOnly()) {
        self.inner = inner
        self.policy = policy
    }

    /// `true` if there is any displayable content after safety filtering.
    var hasContent: Bool {
        (continueWatching?.hasItems ?? false) || !recentlyAdded.isEmpty
    }

    // MARK: - Actions

    /// Initial data load. Called once when the view appears.
    func load() async {
        isLoading = true
        await inner.load()
        applyFilters()
    }

    /// Pull-to-refresh reload. Clears and re-fetches from the Plex server.
    func reload() async {
        isLoading = true
        await inner.reload()
        applyFilters()
    }

    // MARK: - Filtering

    /// Applies the safety policy to the inner view model's raw data.
    /// Called after every data mutation on the inner view model.
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
