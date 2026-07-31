import Foundation
import Observation
import PlinxCore

/// Plinx-owned Home data model.
///
/// Continue Watching remains a Plex hub. Recently-added content is loaded from
/// the same section catalog endpoint used by Library Browse, so Home and
/// Library receive the same item model and rating metadata.
@MainActor
@Observable
final class SafeHomeViewModel {
    private struct CatalogLoadOutcome {
        let results: [LibraryCatalogResult]
        let failureCount: Int
    }

    private(set) var continueWatching: Hub?
    private(set) var recentCatalogs: [LibraryCatalogResult] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let context: PlexAPIContext
    private let settingsManager: SettingsManager
    private let libraryStore: LibraryStore
    private let catalogLoader: any LibraryCatalogLoading
    private var policy: SafetyPolicy
    private var hasLoaded = false
    private var fetchGeneration = 0

    init(
        context: PlexAPIContext,
        settingsManager: SettingsManager,
        libraryStore: LibraryStore,
        policy: SafetyPolicy = .ratingOnly(),
        catalogLoader: (any LibraryCatalogLoading)? = nil
    ) {
        self.context = context
        self.settingsManager = settingsManager
        self.libraryStore = libraryStore
        self.policy = policy
        self.catalogLoader = catalogLoader ?? LibraryCatalogLoader(context: context)
    }

    var hasContent: Bool {
        (continueWatching?.hasItems ?? false) || recentCatalogs.contains { !$0.items.isEmpty }
    }

    var youtarrRecommendationSignals: [String] {
        let continueWatchingTitles = continueWatching?.items
            .compactMap(\.playableItem)
            .map(\.title) ?? []
        let recentTitles = recentCatalogs.flatMap { catalog in
            [catalog.library.title] + catalog.items.map(\.title)
        }
        return continueWatchingTitles + recentTitles
    }

    // MARK: - Actions

    /// Initial data load. Called once when the view appears.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await fetch(preservingContentOnFailure: false)
    }

    func reload() async {
        await fetch(preservingContentOnFailure: true)
    }

    func updatePolicy(_ newPolicy: SafetyPolicy) {
        guard newPolicy != policy else { return }
        policy = newPolicy
        Task { await fetch(preservingContentOnFailure: false) }
    }

    private func fetch(preservingContentOnFailure: Bool) async {
        fetchGeneration += 1
        let generation = fetchGeneration
        let currentPolicy = policy
        isLoading = true
        errorMessage = nil

        if libraryStore.libraries.isEmpty {
            try? await libraryStore.loadLibraries()
        }

        let hiddenIDs = Set(settingsManager.interface.hiddenLibraryIds)
        let libraries = libraryStore.libraries.filter {
            $0.sectionId != nil && !hiddenIDs.contains($0.id)
        }

        async let continueHub = loadContinueWatching(policy: currentPolicy)
        let catalogOutcome = await loadCatalogs(libraries, policy: currentPolicy)
        let loadedContinueHub = await continueHub

        guard generation == fetchGeneration else { return }

        let allCatalogRequestsFailed = !libraries.isEmpty
            && catalogOutcome.failureCount == libraries.count
        if preservingContentOnFailure && hasContent && allCatalogRequestsFailed {
            isLoading = false
            return
        }

        continueWatching = loadedContinueHub
        recentCatalogs = catalogOutcome.results.filter { !$0.items.isEmpty }
        isLoading = false

        if !hasContent && allCatalogRequestsFailed {
            errorMessage = String(localized: "errors.selectServer.loadContent")
        }
    }

    private func loadContinueWatching(policy: SafetyPolicy) async -> Hub? {
        guard let repository = try? HubRepository(context: context),
              let response = try? await repository.getContinueWatchingHub(),
              let plexHub = response.mediaContainer.hub?.first
        else {
            return nil
        }
        return PlinxContentAuthorization.filtered(Hub(plexHub: plexHub), policy: policy)
    }

    private func loadCatalogs(
        _ libraries: [Library],
        policy: SafetyPolicy
    ) async -> CatalogLoadOutcome {
        let batchSize = 4
        var results: [LibraryCatalogResult] = []
        var failureCount = 0

        for start in stride(from: 0, to: libraries.count, by: batchSize) {
            let batch = Array(libraries[start..<min(start + batchSize, libraries.count)])
            let batchResults = await withTaskGroup(of: Result<LibraryCatalogResult, Error>.self) { group in
                for library in batch {
                    group.addTask { @MainActor [catalogLoader, policy] in
                        do {
                            return .success(
                                try await catalogLoader.recentItems(
                                    for: library,
                                    limit: 20,
                                    policy: policy
                                )
                            )
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                var loaded: [LibraryCatalogResult] = []
                for await result in group {
                    switch result {
                    case let .success(catalog):
                        loaded.append(catalog)
                    case .failure:
                        failureCount += 1
                    }
                }
                return loaded
            }
            results.append(contentsOf: batchResults)
        }

        let order = Dictionary(uniqueKeysWithValues: libraries.enumerated().map { ($0.element.id, $0.offset) })
        let sortedResults = results.sorted {
            order[$0.library.id, default: .max] < order[$1.library.id, default: .max]
        }
        return CatalogLoadOutcome(results: sortedResults, failureCount: failureCount)
    }
}
