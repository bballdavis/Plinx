import Foundation
import Observation

/// The profile's favorites, for the **My Favorites** row on the Plinx Home.
///
/// Kids favorite movies, shows, seasons and episodes from the detail page and
/// the card menus (`MediaQuickActions`). Every ready server that supports
/// favorites is asked through its `MediaServices`, so the safety boundary
/// (`SafeFavoritesService`) filters the list before it arrives here. Plex
/// favorites are kept on the device for each profile (`FavoritesStore`);
/// Jellyfin favorites belong to the Jellyfin user.
///
/// `rowItems` checks every title again when the row is drawn: against the
/// current policy, and against the libraries the profile hides. A stricter
/// policy or a newly hidden library therefore takes a title off at once, and a
/// policy change discards everything loaded under the old one.
@MainActor
@Observable
final class HomeFavoritesStore {
    /// The Home section id, also stored in `plinx.homeSectionOrder`.
    static let sectionKey = "favorites"

    /// What a kid can favorite (`MediaQuickActions.canFavorite`).
    static let kinds: Set<MediaKind> = [.movie, .series, .season, .episode]

    /// One server's favorites.
    struct Source {
        let server: ServerIdentity
        let favorites: @MainActor () async throws -> [MediaItem]
    }

    /// Favorites by server, as the boundary returned them on the last load.
    private(set) var favoritesByServer: [ServerIdentity: [MediaItem]] = [:]

    @ObservationIgnored private let gate: ContentSafetyGate
    @ObservationIgnored private var loadedPolicyRevision: Int?

    init(gate: ContentSafetyGate = .shared) {
        self.gate = gate
    }

    // MARK: - Loading

    /// Loads the favorites of every ready server of the profile that supports them.
    func load(registry: ServerRegistry) async {
        await load(sources: Self.sources(in: registry))
    }

    /// The ready servers of the profile that support favorites, through their filtered `MediaServices`.
    static func sources(in registry: ServerRegistry) -> [Source] {
        registry.activeSessions.compactMap { session in
            guard let services = session.services, services.capabilities.favorites else { return nil }
            return Source(server: session.identity) { try await services.favorites.favorites() }
        }
    }

    /// Replaces the favorites of `sources`' servers and drops the servers that are no longer listed. A server
    /// that fails keeps what it showed. Favorites that arrive under a policy that changed meanwhile are dropped.
    func load(sources: [Source]) async {
        let policyRevision = gate.revision
        if loadedPolicyRevision != policyRevision {
            // Fail closed: nothing loaded under the previous policy stays.
            loadedPolicyRevision = policyRevision
            favoritesByServer = [:]
        }

        var loaded: [ServerIdentity: [MediaItem]] = [:]
        await withTaskGroup(of: (ServerIdentity, [MediaItem]?).self) { group in
            for source in sources {
                group.addTask { @MainActor in
                    (source.server, try? await source.favorites())
                }
            }
            for await (server, items) in group {
                if let items {
                    loaded[server] = items
                }
            }
        }

        guard !Task.isCancelled, policyRevision == gate.revision, loadedPolicyRevision == policyRevision else {
            return
        }
        let servers = Set(sources.map(\.server))
        var next = favoritesByServer.filter { servers.contains($0.key) }
        next.merge(loaded) { _, new in new }
        if next != favoritesByServer {
            favoritesByServer = next
        }
    }

    // MARK: - Row

    /// The row's titles, checked again against the current policy and the profile's hidden libraries.
    func rowItems(serverOrder: [ServerIdentity], hiddenLibraries: Set<LibraryIdentity>) -> [MediaDisplayItem] {
        Self.rowItems(
            from: favoritesByServer,
            serverOrder: serverOrder,
            hiddenLibraries: hiddenLibraries,
            gate: gate,
        )
    }

    /// Favorites allowed by `gate`, from the servers in `serverOrder` (the profile's enabled servers) and the
    /// libraries the profile shows. A favorite whose library is unknown (Jellyfin) is left out while the profile
    /// hides any library of its server, as in search. Titles are listed once, by title; a show's seasons and
    /// episodes follow it in order.
    static func rowItems(
        from favoritesByServer: [ServerIdentity: [MediaItem]],
        serverOrder: [ServerIdentity],
        hiddenLibraries: Set<LibraryIdentity>,
        gate: ContentSafetyGate,
    ) -> [MediaDisplayItem] {
        var seen: Set<String> = []
        var candidates: [(rank: Int, media: MediaItem)] = []
        for (rank, server) in serverOrder.enumerated() {
            for media in favoritesByServer[server] ?? [] {
                let item = MediaDisplayItem.playable(media)
                guard kinds.contains(media.type),
                      gate.isAllowed(media),
                      PlinxLibraryVisibility.isVisible(item, on: server, hiddenLibraries: hiddenLibraries),
                      seen.insert(HomeLibraryGrouping.itemKey(item)).inserted
                else { continue }
                candidates.append((rank, media))
            }
        }
        return candidates
            .sorted { lhs, rhs in isOrderedBefore(lhs.media, rhs.media, lhsRank: lhs.rank, rhsRank: rhs.rank) }
            .map { MediaDisplayItem.playable($0.media) }
    }

    private static func isOrderedBefore(_ lhs: MediaItem, _ rhs: MediaItem, lhsRank: Int, rhsRank: Int) -> Bool {
        let title = showTitle(of: lhs).localizedStandardCompare(showTitle(of: rhs))
        if title != .orderedSame {
            return title == .orderedAscending
        }
        if kindOrder(lhs.type) != kindOrder(rhs.type) {
            return kindOrder(lhs.type) < kindOrder(rhs.type)
        }
        if (lhs.parentIndex ?? 0) != (rhs.parentIndex ?? 0) {
            return (lhs.parentIndex ?? 0) < (rhs.parentIndex ?? 0)
        }
        if (lhs.index ?? 0) != (rhs.index ?? 0) {
            return (lhs.index ?? 0) < (rhs.index ?? 0)
        }
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.id < rhs.id
    }

    /// Seasons and episodes sort under their show.
    private static func showTitle(of media: MediaItem) -> String {
        switch media.type {
        case .episode:
            media.grandparentTitle ?? media.title
        case .season:
            media.parentTitle ?? media.title
        default:
            media.title
        }
    }

    private static func kindOrder(_ kind: MediaKind) -> Int {
        switch kind {
        case .season: 1
        case .episode: 2
        default: 0
        }
    }
}
