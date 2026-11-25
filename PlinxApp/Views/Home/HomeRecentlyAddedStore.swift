import Foundation
import Observation

/// The newest titles of each visible library, for the Plinx Home's
/// recently-added rows (`HomeRecentlyAddedProjection` groups them).
///
/// Each library is read with `LibraryCatalogLoader`, through the server's
/// `MediaServices`, so the safety boundary filters titles before they reach
/// Home; the view filters again with `ContentSafetyGate` when it draws.
/// Libraries load a few at a time, a library that fails is simply absent, and
/// a server that comes back only reloads its own libraries.
@MainActor
@Observable
final class HomeRecentlyAddedStore {
    /// Titles per library, as the Home showed before the absorbed provider layer.
    static let itemLimit = 20
    private static let batchSize = 4
    /// Full reloads are spaced out: returning to the app within this interval keeps the rows.
    private static let staleInterval: TimeInterval = 15 * 60

    /// Non-empty catalogs, in the profile's library order.
    private(set) var catalogs: [LibraryCatalogResult] = []
    private(set) var isLoading = false
    /// The first sync finished, even when there was nothing to load.
    private(set) var hasSynced = false
    /// Every request of the last load failed and nothing is shown.
    private(set) var hasFailed = false

    @ObservationIgnored private var libraries: [Library] = []
    @ObservationIgnored private var itemsByLibrary: [LibraryIdentity: [MediaDisplayItem]] = [:]
    @ObservationIgnored private var knownReadyServers: Set<ServerIdentity> = []
    @ObservationIgnored private var loadedPolicyRevision: Int?
    @ObservationIgnored private var loadedContentRevisions: [ServerIdentity: Int] = [:]
    @ObservationIgnored private var lastLoad: Date?
    @ObservationIgnored private var activeLoads = 0

    private var gate: ContentSafetyGate {
        .shared
    }

    // MARK: - Loading

    /// Shows `libraries` (the profile's visible libraries, in order): loads the
    /// ones not loaded yet, reloads those of servers that became ready, and
    /// drops the rest. A new content policy discards everything first.
    func sync(libraries: [Library], registry: ServerRegistry) async {
        let eligible = libraries.filter(Self.isEligible)
        let identities = Set(eligible.map(\.identity))
        var reloadsEverything = false
        if loadedPolicyRevision != gate.revision {
            // Fail closed: nothing loaded under the previous policy stays on screen.
            loadedPolicyRevision = gate.revision
            itemsByLibrary = [:]
            reloadsEverything = true
        }
        let ready = registry.readyServers
        let arrived = ready.subtracting(knownReadyServers)
        knownReadyServers = ready
        self.libraries = eligible
        itemsByLibrary = itemsByLibrary.filter { identities.contains($0.key) }
        publish()

        let targets = eligible.filter { library in
            reloadsEverything || itemsByLibrary[library.identity] == nil || arrived.contains(library.server)
        }
        if !targets.isEmpty {
            await load(targets, registry: registry)
        }
        hasSynced = true
    }

    /// Pull to refresh and Retry: every library again. Libraries that fail keep what they showed.
    func reload(registry: ServerRegistry) async {
        await load(libraries, registry: registry)
    }

    /// Reloads the servers whose watch state or media changed since they were
    /// loaded. A policy change is left to `sync`, which reloads everything.
    func refreshChangedServers(registry: ServerRegistry) async {
        guard loadedPolicyRevision == gate.revision else { return }
        let changed = Set(loadedContentRevisions.compactMap { server, revision in
            registry.services(for: server).map { Self.contentRevision(of: $0) } != revision ? server : nil
        })
        guard !changed.isEmpty else { return }
        await load(libraries.filter { changed.contains($0.server) }, registry: registry)
    }

    /// Reloads every library once the last load is old enough, e.g. when the app comes back to the front.
    func refreshIfStale(registry: ServerRegistry, now: Date = Date()) async {
        guard hasSynced, let lastLoad, now.timeIntervalSince(lastLoad) >= Self.staleInterval else { return }
        await reload(registry: registry)
    }

    private func load(_ targets: [Library], registry: ServerRegistry) async {
        guard !targets.isEmpty else { return }
        let policyRevision = gate.revision
        activeLoads += 1
        isLoading = true
        defer {
            activeLoads -= 1
            isLoading = activeLoads > 0
        }

        var loaded: [LibraryIdentity: [MediaDisplayItem]] = [:]
        var revisions: [ServerIdentity: Int] = [:]
        var failureCount = 0
        for start in stride(from: 0, to: targets.count, by: Self.batchSize) {
            let batch = Array(targets[start ..< min(start + Self.batchSize, targets.count)])
            await withTaskGroup(of: (LibraryIdentity, [MediaDisplayItem]?).self) { group in
                for library in batch {
                    guard let services = registry.services(for: library.server) else {
                        failureCount += 1
                        continue
                    }
                    revisions[library.server] = Self.contentRevision(of: services)
                    group.addTask { @MainActor in
                        let catalog = try? await LibraryCatalogLoader(services: services)
                            .recentItems(for: library, limit: Self.itemLimit)
                        return (library.identity, catalog?.items)
                    }
                }
                for await (identity, items) in group {
                    if let items {
                        loaded[identity] = items
                    } else {
                        failureCount += 1
                    }
                }
            }
            if Task.isCancelled { break }
        }

        // Titles loaded under a policy that changed meanwhile are dropped; `sync` reloads them.
        guard policyRevision == gate.revision, loadedPolicyRevision == policyRevision else { return }
        let wanted = Set(libraries.map(\.identity))
        for (identity, items) in loaded where wanted.contains(identity) {
            itemsByLibrary[identity] = items
        }
        loadedContentRevisions.merge(revisions) { _, new in new }
        lastLoad = Date()
        publish()
        if !Task.isCancelled {
            hasFailed = catalogs.isEmpty && loaded.isEmpty && failureCount > 0
        }
    }

    private func publish() {
        let next = libraries.compactMap { library -> LibraryCatalogResult? in
            guard let items = itemsByLibrary[library.identity], !items.isEmpty else { return nil }
            return LibraryCatalogResult(library: library, items: items)
        }
        if next != catalogs {
            catalogs = next
        }
        if !next.isEmpty {
            hasFailed = false
        }
    }

    // MARK: - Libraries

    /// Movie, TV and other-video libraries. Plex's shared items and
    /// collection or playlist libraries have no recently-added row.
    static func isEligible(_ library: Library) -> Bool {
        guard !library.isShared else { return false }
        switch library.type {
        case .movie, .series, .clip:
            return true
        case .season, .episode, .collection, .playlist, .folder, .unknown:
            return false
        }
    }

    /// What a server's Home rows depend on, apart from the content policy.
    private static func contentRevision(of services: MediaServices) -> Int {
        services.watchStateRevision + services.mediaRevision
    }
}
