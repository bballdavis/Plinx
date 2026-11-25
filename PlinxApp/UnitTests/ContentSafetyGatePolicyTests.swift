// ─────────────────────────────────────────────────────────────────────────────
// ContentSafetyGatePolicyTests.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// Unit tests for `ContentSafetyGate` judged against an explicit
// `SafetyPolicy` (`ContentSafetyGate(policy:)`, the one way to check content
// against a policy other than the shared gate's), and for the playlist Play /
// Shuffle selection built on the gate (`PlinxPlaylistPlaybackSelection`).
//
// Running:
//   Select the Plinx-iOS-UnitTests target in Xcode and press Cmd+U.
//
// Why these tests exist:
//   Every item follows the same parent-selected rating policy. Plex clips and
//   home videos commonly omit a rating, but that is not evidence that they are
//   allowed. They remain hidden until the parent explicitly enables unrated
//   content. Adult-only ratings (NC-17, X, an age certificate of 18 or older
//   such as 18, KR-19 or R21) sit above every ceiling and are rejected even
//   when unrated content is allowed. An episode without a rating of its own
//   takes its series' rating; one whose series is unknown is rejected under
//   every policy.
//
//   Quick-reference regression table:
//   ┌─────────────────────────────────┬────────────────────┬──────────────────┐
//   │ Item                            │ allowUnrated=false │ allowUnrated=true│
//   ├─────────────────────────────────┼────────────────────┼──────────────────┤
//   │ Clip, no contentRating          │ ❌ blocked          │ ✅ allowed        │
//   │ Movie, no contentRating         │ ❌ blocked          │ ✅ allowed        │
//   │ Movie, contentRating="R"        │ ❌ blocked (G max)  │ ❌ blocked        │
//   │ Movie, contentRating="NC-17"/X  │ ❌ blocked          │ ❌ always blocked │
//   │ Movie, contentRating="G"        │ ✅ allowed          │ ✅ allowed        │
//   │ Episode, unrated, TV-Y series   │ ✅ allowed          │ ✅ allowed        │
//   │ Episode, unrated, TV-MA series  │ ❌ blocked          │ ❌ blocked        │
//   │ Episode, unrated, series unknown│ ❌ blocked          │ ❌ blocked        │
//   │ Collection                      │ ✅ always allowed   │ ✅ always allowed │
//   │ Playlist                        │ ✅ always allowed   │ ✅ always allowed │
//   └─────────────────────────────────┴────────────────────┴──────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class ContentSafetyGatePolicyTests: XCTestCase {

    // MARK: - Policies

    /// Default parent-managed policy; excludes every unrated item.
    private let strictPolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)

    /// Permissive policy; allows all unrated content (used for contrast).
    private let permissivePolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: true)

    /// The most permissive policy a parent can choose: highest ceilings and unrated allowed.
    private let widestPolicy = SafetyPolicy.ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: true)

    private func makeGate(_ policy: SafetyPolicy) -> ContentSafetyGate {
        ContentSafetyGate(policy: policy)
    }

    // MARK: - Clip items follow the same unrated policy

    func test_clipItem_noRating_blockedWithStrictPolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: nil)
        XCTAssertFalse(
            makeGate(strictPolicy).isAllowed(item),
            "Missing clip metadata must fail closed when unrated content is disabled"
        )
    }

    func test_clipItem_noRating_allowedWithPermissivePolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: nil)
        XCTAssertTrue(
            makeGate(permissivePolicy).isAllowed(item),
            "Clip items should pass under permissive policy too"
        )
    }

    func test_clipItem_withRating_allowedWhenWithinPolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: "G")
        XCTAssertTrue(
            makeGate(strictPolicy).isAllowed(item),
            "Clip items carrying a G rating must be allowed under a G-max policy"
        )
    }

    // MARK: - Movie items without rating

    func test_movieItem_noRating_blockedByStrictPolicy() {
        let item = MediaItem.fixture(type: .movie, contentRating: nil)
        XCTAssertFalse(
            makeGate(strictPolicy).isAllowed(item),
            "Movie items without a rating must be blocked when allowUnrated=false"
        )
    }

    func test_movieItem_noRating_allowedByPermissivePolicy() {
        let item = MediaItem.fixture(type: .movie, contentRating: nil)
        XCTAssertTrue(
            makeGate(permissivePolicy).isAllowed(item),
            "Movie items without a rating must be allowed when allowUnrated=true"
        )
    }

    // MARK: - Rating gate

    func test_movieItem_ratedG_allowed() {
        let item = MediaItem.fixture(type: .movie, contentRating: "G")
        XCTAssertTrue(makeGate(strictPolicy).isAllowed(item))
    }

    func test_movieItem_ratedPG_blocked() {
        let item = MediaItem.fixture(type: .movie, contentRating: "PG")
        XCTAssertFalse(
            makeGate(strictPolicy).isAllowed(item),
            "PG movie must be blocked by a G-max policy"
        )
    }

    func test_movieItem_ratedR_blocked() {
        let item = MediaItem.fixture(type: .movie, contentRating: "R")
        XCTAssertFalse(
            makeGate(strictPolicy).isAllowed(item),
            "R-rated movie must be blocked by a G-max policy"
        )
        XCTAssertFalse(
            makeGate(permissivePolicy).isAllowed(item),
            "Allowing unrated content must not lift the rating ceiling"
        )
    }

    // MARK: - Adult-only ratings are always rejected

    func test_adultOnlyRatings_blockedEvenByWidestPolicy() {
        let widest = makeGate(widestPolicy)
        for rating in ["NC-17", "X", "18", "R18+", "KR-19", "sg/R21", "21+", "18A"] {
            let item = MediaItem.fixture(id: "adult-\(rating)", type: .movie, contentRating: rating)
            XCTAssertFalse(
                widest.isAllowed(item),
                "\(rating) must be rejected even with the highest ceilings and unrated content allowed"
            )
            XCTAssertFalse(
                widest.isAllowed(MediaDisplayItem.playable(item)),
                "\(rating) must be rejected when wrapped as a display item"
            )
            XCTAssertNil(widest.shown(MediaDisplayItem.playable(item)), "\(rating) must never be shown")
        }
    }

    func test_hubWithOnlyAdultOnlyItems_isRemovedByWidestPolicy() {
        let adult = MediaItem.fixture(id: "adult", type: .movie, contentRating: "NC-17")
        let hub = Hub(id: "hub.movie.adult", title: "Adult", items: [.playable(adult)])
        XCTAssertNil(
            makeGate(widestPolicy).filter(hub),
            "A hub with only adult-only items must be removed under every policy"
        )
    }

    // MARK: - Global ceilings apply to YouTube-like clips

    func test_globalTVRatingCeiling_appliesToYouTubeLikeClips() {
        let tvY = MediaItem.fixture(id: "tv-y", type: .clip, contentRating: "TV-Y")
        let tvPG = MediaItem.fixture(id: "tv-pg", type: .clip, contentRating: "TV-PG")
        let raisedPolicy = SafetyPolicy.ratingOnly(
            maxMovie: .g,
            maxTV: .tvPg,
            allowUnrated: false
        )

        XCTAssertTrue(makeGate(strictPolicy).isAllowed(tvY))
        XCTAssertFalse(makeGate(strictPolicy).isAllowed(tvPG))
        XCTAssertTrue(makeGate(raisedPolicy).isAllowed(tvPG))
    }

    func test_globalUnratedToggle_appliesToYouTubeLikeClips() {
        let unrated = MediaItem.fixture(id: "unrated-youtube", type: .clip, contentRating: nil)

        XCTAssertFalse(makeGate(strictPolicy).isAllowed(unrated))
        XCTAssertTrue(makeGate(permissivePolicy).isAllowed(unrated))
    }

    // MARK: - Episodes are judged against their series

    func test_unratedEpisode_takesItsSeriesRating() async {
        for policy in [strictPolicy, permissivePolicy] {
            let gate = makeGate(policy)
            await gate.learnSeries(of: [.kidsSeries, .adultSeries], lookup: Self.noLookup)

            XCTAssertTrue(
                gate.isAllowed(MediaItem.fixture(id: "kids-ep", type: .episode, series: "kids-show")),
                "An unrated episode of a TV-Y series counts as TV-Y, not as unrated (allowUnrated=\(policy.allowUnrated))"
            )
            XCTAssertFalse(
                gate.isAllowed(MediaItem.fixture(id: "adult-ep", type: .episode, series: "adult-show")),
                "An unrated episode of a TV-MA series counts as TV-MA (allowUnrated=\(policy.allowUnrated))"
            )
        }
    }

    func test_unratedEpisodeOfAnUnknownSeries_blockedByEveryPolicy() {
        let episode = MediaItem.fixture(id: "orphan-ep", type: .episode, series: "unknown-show")
        for policy in [strictPolicy, permissivePolicy, widestPolicy] {
            XCTAssertFalse(
                makeGate(policy).isAllowed(episode),
                "Without its series' rating an unrated episode must stay blocked (allowUnrated=\(policy.allowUnrated))"
            )
        }
    }

    // MARK: - Containers may display only after their children are filtered

    func test_collection_alwaysAllowed() {
        let displayItem: MediaDisplayItem = .collection(CollectionMediaItem(
            id: "col1",
            key: "/library/collections/col1/children",
            guid: "plex://collection/col1",
            type: .collection,
            title: "Test Collection",
            summary: nil,
            thumbPath: nil,
            childCount: nil,
            minYear: nil,
            maxYear: nil,
            server: .safetyTestServer
        ))
        XCTAssertTrue(
            makeGate(strictPolicy).isAllowed(displayItem),
            "Collections must always pass safety filtering (children are filtered individually)"
        )
    }

    func test_playlist_alwaysAllowed() {
        let displayItem: MediaDisplayItem = .playlist(PlaylistMediaItem(
            id: "pl1",
            key: "/playlists/pl1/items",
            guid: "plex://playlist/pl1",
            type: .playlist,
            title: "Test Playlist",
            summary: nil,
            compositePath: nil,
            duration: nil,
            leafCount: nil,
            playlistType: "video",
            server: .safetyTestServer
        ))
        XCTAssertTrue(
            makeGate(strictPolicy).isAllowed(displayItem),
            "Playlists must always pass safety filtering (entries are filtered individually)"
        )
    }

    // MARK: - Hub-level filtering

    func test_hubWithUnratedClipItems_isRemovedByStrictFilter() {
        let clipItem = MediaItem.fixture(type: .clip, contentRating: nil)
        let hub = Hub(id: "hub.clip.recent", title: "Other Videos", items: [.playable(clipItem)])
        XCTAssertNil(
            makeGate(strictPolicy).filter(hub),
            "An unrated clip hub must be removed when the parent has not enabled unrated content"
        )
    }

    func test_hubWithMovieNoRating_removedByStrictFilter() {
        let movieItem = MediaItem.fixture(type: .movie, contentRating: nil)
        let hub = Hub(id: "hub.movie.new", title: "New Movies", items: [.playable(movieItem)])
        XCTAssertNil(
            makeGate(strictPolicy).filter(hub),
            "A hub containing only unrated movie items must be nil after strict safety filtering"
        )
    }

    func test_hubFilteringKeepsOnlyAllowedItemsAndRecountsSize() throws {
        let allowed = MediaItem.fixture(id: "allowed", type: .movie, contentRating: "G")
        let blocked = MediaItem.fixture(id: "blocked", type: .movie, contentRating: "R")
        let hub = Hub(id: "hub.movie.mixed", title: "Mixed", items: [.playable(blocked), .playable(allowed)])

        let filtered = try XCTUnwrap(makeGate(strictPolicy).filter(hub))

        XCTAssertEqual(filtered.items.map(\.id), ["allowed"])
        XCTAssertEqual(filtered.size, 1)
    }

    /// Only filtering removes a hub: one the server sent empty holds nothing to block, and stays.
    func test_hubTheServerSentEmpty_isKept() throws {
        let hub = Hub(id: "hub.movie.empty", title: "Empty", items: [])

        let filtered = try XCTUnwrap(makeGate(strictPolicy).filter(hub))

        XCTAssertTrue(filtered.items.isEmpty)
    }

    // MARK: - Playlist Play / Shuffle selection

    func test_playlistSelectionBuildsQueueOnlyFromAuthorizedEntries() {
        let gate = makeGate(strictPolicy)
        let allowed = MediaItem.fixture(id: "allowed", type: .movie, contentRating: "G")
        let blocked = MediaItem.fixture(id: "blocked", type: .movie, contentRating: "R")
        let adult = MediaItem.fixture(id: "adult", type: .movie, contentRating: "NC-17")
        let unrated = MediaItem.fixture(id: "unrated", type: .clip, contentRating: nil)
        let source: [MediaDisplayItem] = [
            .playable(blocked),
            .playable(allowed),
            .playable(adult),
            .playable(unrated)
        ]

        let authorized = PlinxPlaylistPlaybackSelection.authorizedItems(from: source, gate: gate)

        XCTAssertEqual(authorized.map(\.id), ["allowed"])
        XCTAssertEqual(
            PlinxPlaylistPlaybackSelection.item(from: source, gate: gate, shuffled: false)?.id,
            "allowed"
        )
        XCTAssertEqual(
            PlinxPlaylistPlaybackSelection.item(from: source, gate: gate, shuffled: true)?.id,
            "allowed",
            "Shuffle must only pick from authorized entries"
        )
    }

    func test_playlistSelectionReturnsNothingWhenNoEntryIsAuthorized() {
        let gate = makeGate(strictPolicy)
        let source: [MediaDisplayItem] = [
            .playable(MediaItem.fixture(id: "blocked", type: .movie, contentRating: "R")),
            .playable(MediaItem.fixture(id: "adult", type: .movie, contentRating: "X")),
            .playable(MediaItem.fixture(id: "unrated", type: .clip, contentRating: nil))
        ]

        XCTAssertTrue(PlinxPlaylistPlaybackSelection.authorizedItems(from: source, gate: gate).isEmpty)
        XCTAssertNil(PlinxPlaylistPlaybackSelection.item(from: source, gate: gate, shuffled: false))
        XCTAssertNil(PlinxPlaylistPlaybackSelection.item(from: source, gate: gate, shuffled: true))
    }

    /// Play starts an unrated episode of an allowed series, and never one of a blocked or unknown series.
    func test_playlistSelectionJudgesEpisodesAgainstTheirSeries() async {
        let gate = makeGate(strictPolicy)
        await gate.learnSeries(of: [.kidsSeries, .adultSeries], lookup: Self.noLookup)
        let source: [MediaDisplayItem] = [
            .playable(MediaItem.fixture(id: "adult-ep", type: .episode, series: "adult-show")),
            .playable(MediaItem.fixture(id: "orphan-ep", type: .episode, series: "unknown-show")),
            .playable(MediaItem.fixture(id: "kids-ep", type: .episode, series: "kids-show"))
        ]

        XCTAssertEqual(PlinxPlaylistPlaybackSelection.authorizedItems(from: source, gate: gate).map(\.id), ["kids-ep"])
        XCTAssertEqual(PlinxPlaylistPlaybackSelection.item(from: source, gate: gate, shuffled: true)?.id, "kids-ep")
    }

    // MARK: - Helpers

    /// The series these tests teach the gate come with their own ratings, so it never looks one up.
    private static let noLookup: ContentSafetyGate.SeriesLookup = { _ in
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: - MediaItem test fixtures

private extension ServerIdentity {
    static let safetyTestServer = ServerIdentity(provider: .plex, id: "safety-test-server")
}

private extension MediaItem {
    static let kidsSeries = MediaItem.fixture(id: "kids-show", type: .series, contentRating: "TV-Y")
    static let adultSeries = MediaItem.fixture(id: "adult-show", type: .series, contentRating: "TV-MA")

    /// Convenience initialiser for test fixtures.
    /// Only requires the fields that meaningfully vary between tests.
    /// - Parameter series: the series of an episode (its grandparent), on the same server.
    static func fixture(
        id: String = "fixture-id",
        type: MediaKind = .movie,
        contentRating: String? = nil,
        series: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: .safetyTestServer, itemID: id),
            guid: "plex://\(type.rawValue)/\(id)",
            summary: nil,
            title: "Test Item",
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: series,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: contentRating,
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
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        )
    }
}
