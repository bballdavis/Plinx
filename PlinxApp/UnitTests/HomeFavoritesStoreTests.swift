import PlinxCore
import XCTest
@testable import Plinx

/// My Favorites on Home (`HomeFavoritesStore`): the row shows only titles the
/// current policy allows, from libraries the profile shows, and nothing loaded
/// under an earlier policy survives a policy change.
@MainActor
final class HomeFavoritesStoreTests: XCTestCase {
    private let plex = ServerIdentity(provider: .plex, id: "favorites-plex")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "favorites-jellyfin")

    private func makeGate() -> ContentSafetyGate {
        ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg, maxTV: .tvY7))
    }

    // MARK: - Row

    func test_rowDropsEveryTitleThePolicyBlocks() {
        let favorites = [
            favorite("allowed-movie", on: plex, rating: "PG"),
            favorite("over-ceiling", on: plex, rating: "R"),
            favorite("unrated", on: plex, rating: nil),
            favorite("adult-only", on: plex, rating: "NC-17"),
            favorite("allowed-show", on: plex, rating: "TV-Y7", type: .series),
            favorite("over-ceiling-show", on: plex, rating: "TV-14", type: .series),
        ]

        let row = HomeFavoritesStore.rowItems(
            from: [plex: favorites],
            serverOrder: [plex],
            hiddenLibraries: [],
            gate: makeGate()
        )

        XCTAssertEqual(row.map(\.id), ["allowed-movie", "allowed-show"])
    }

    func test_rowLeavesOutHiddenLibrariesAndFailsClosedWithoutALibrary() {
        let hidden: Set<LibraryIdentity> = [LibraryIdentity(server: plex, libraryID: "adults")]
        let row = HomeFavoritesStore.rowItems(
            from: [
                plex: [
                    favorite("in-hidden-library", on: plex, library: "adults"),
                    favorite("in-shown-library", on: plex, library: "kids"),
                    favorite("no-library-on-plex", on: plex),
                ],
                jellyfin: [favorite("no-library-on-jellyfin", on: jellyfin)],
            ],
            serverOrder: [plex, jellyfin],
            hiddenLibraries: hidden,
            gate: makeGate()
        )

        // A favorite that names no library is hidden while its server hides any library, as in search.
        XCTAssertEqual(row.map(\.id), ["in-shown-library", "no-library-on-jellyfin"])
    }

    func test_rowListsFavoritableKindsFromEnabledServersOnce() {
        let removed = ServerIdentity(provider: .plex, id: "removed-server")
        let row = HomeFavoritesStore.rowItems(
            from: [
                plex: [
                    favorite("a-movie", on: plex),
                    favorite("a-movie", on: plex),
                    favorite("b-clip", on: plex, type: .clip),
                    favorite("c-collection", on: plex, type: .collection),
                ],
                jellyfin: [favorite("a-movie", on: jellyfin)],
                removed: [favorite("d-movie", on: removed)],
            ],
            serverOrder: [plex, jellyfin],
            hiddenLibraries: [],
            gate: makeGate()
        )

        XCTAssertEqual(row.map(\.id), ["a-movie", "a-movie"])
        XCTAssertEqual(row.map(\.server), [plex, jellyfin], "the same ID on two servers is two titles")
    }

    func test_rowSortsByTitleWithSeasonsAndEpisodesUnderTheirShow() {
        let favorites = [
            favorite("zebra", on: plex, title: "Zebra Movie"),
            favorite("episode-2-1", on: plex, rating: "TV-Y", type: .episode, title: "Pilot",
                     show: "Bluey", parentIndex: 2, index: 1),
            favorite("episode-1-3", on: plex, rating: "TV-Y", type: .episode, title: "Hammerbarn",
                     show: "Bluey", parentIndex: 1, index: 3),
            favorite("season-1", on: plex, rating: "TV-Y", type: .season, title: "Season 1",
                     show: "Bluey", index: 1),
            favorite("show", on: plex, rating: "TV-Y", type: .series, title: "Bluey"),
            favorite("apple", on: plex, title: "apple movie"),
        ]

        let row = HomeFavoritesStore.rowItems(
            from: [plex: favorites],
            serverOrder: [plex],
            hiddenLibraries: [],
            gate: makeGate()
        )

        XCTAssertEqual(row.map(\.id), ["apple", "show", "season-1", "episode-1-3", "episode-2-1", "zebra"])
    }

    // MARK: - Store

    func test_stricterPolicyHidesLoadedFavoritesAtOnce() async {
        let gate = ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg13, maxTV: .tv14))
        let store = HomeFavoritesStore(gate: gate)
        await store.load(sources: [
            source(plex, [favorite("pg", on: plex, rating: "PG"), favorite("pg-13", on: plex, rating: "PG-13")]),
        ])
        XCTAssertEqual(store.rowItems(serverOrder: [plex], hiddenLibraries: []).map(\.id), ["pg", "pg-13"])

        gate.policy = .ratingOnly(maxMovie: .pg, maxTV: .tvY7)

        XCTAssertEqual(store.rowItems(serverOrder: [plex], hiddenLibraries: []).map(\.id), ["pg"])
    }

    func test_policyChangeDiscardsFavoritesEvenWhenTheReloadFails() async {
        let gate = makeGate()
        let store = HomeFavoritesStore(gate: gate)
        await store.load(sources: [source(plex, [favorite("movie", on: plex)])])
        XCTAssertEqual(store.favoritesByServer[plex]?.map(\.id), ["movie"])

        // Without a policy change a failing server keeps what it showed.
        await store.load(sources: [failingSource(plex)])
        XCTAssertEqual(store.favoritesByServer[plex]?.map(\.id), ["movie"])

        gate.policy = .ratingOnly(maxMovie: .g, maxTV: .tvY)
        await store.load(sources: [failingSource(plex)])

        XCTAssertTrue(store.favoritesByServer.isEmpty, "favorites loaded under the old policy must not stay")
    }

    func test_loadDropsServersThatLeftTheProfile() async {
        let store = HomeFavoritesStore(gate: makeGate())
        await store.load(sources: [
            source(plex, [favorite("plex-movie", on: plex)]),
            source(jellyfin, [favorite("jellyfin-movie", on: jellyfin)]),
        ])
        XCTAssertEqual(Set(store.favoritesByServer.keys), [plex, jellyfin])

        await store.load(sources: [source(plex, [favorite("plex-movie", on: plex)])])

        XCTAssertEqual(Set(store.favoritesByServer.keys), [plex])
    }

    // MARK: - Helpers

    private func source(_ server: ServerIdentity, _ items: [MediaItem]) -> HomeFavoritesStore.Source {
        HomeFavoritesStore.Source(server: server) { items }
    }

    private func failingSource(_ server: ServerIdentity) -> HomeFavoritesStore.Source {
        HomeFavoritesStore.Source(server: server) { throw URLError(.notConnectedToInternet) }
    }

    private func favorite(
        _ id: String,
        on server: ServerIdentity,
        rating: String? = "G",
        type: MediaKind = .movie,
        title: String? = nil,
        library: String? = nil,
        show: String? = nil,
        parentIndex: Int? = nil,
        index: Int? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: "\(server.provider.rawValue)://\(id)",
            summary: nil,
            title: title ?? id,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: rating,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: type == .episode ? show : nil,
            parentTitle: type == .season ? show : nil,
            parentIndex: parentIndex,
            index: index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
            librarySectionID: library
        )
    }
}
