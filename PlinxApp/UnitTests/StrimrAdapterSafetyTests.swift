// ─────────────────────────────────────────────────────────────────────────────
// StrimrAdapterSafetyTests.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// Unit tests for `PlinxContentRules` (formerly `StrimrAdapter`) — the
// synchronous content checks that apply PlinxCore's `SafetyInterceptor` rules
// to app media types against an explicit `SafetyPolicy`, and for the playlist
// Play / Shuffle selection built on them (`PlinxPlaylistPlaybackSelection`).
//
// Running:
//   Select the Plinx-iOS-UnitTests target in Xcode and press Cmd+U.
//
// Why these tests exist:
//   Every item follows the same parent-selected rating policy. Plex clips and
//   home videos commonly omit a rating, but that is not evidence that they are
//   allowed. They remain hidden until the parent explicitly enables unrated
//   content. Adult-only ratings (NC-17, X, an 18 certificate) sit above every
//   ceiling and are rejected even when unrated content is allowed.
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
//   │ Collection                      │ ✅ always allowed   │ ✅ always allowed │
//   │ Playlist                        │ ✅ always allowed   │ ✅ always allowed │
//   └─────────────────────────────────┴────────────────────┴──────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

import XCTest
import PlinxCore
@testable import Plinx

final class StrimrAdapterSafetyTests: XCTestCase {

    // MARK: - Policies

    /// Default parent-managed policy; excludes every unrated item.
    private let strictPolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)

    /// Permissive policy; allows all unrated content (used for contrast).
    private let permissivePolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: true)

    /// The most permissive policy a parent can choose: highest ceilings and unrated allowed.
    private let widestPolicy = SafetyPolicy.ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: true)

    // MARK: - Clip items follow the same unrated policy

    func test_clipItem_noRating_blockedWithStrictPolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: nil)
        XCTAssertFalse(
            PlinxContentRules.isAllowed(item, policy: strictPolicy),
            "Missing clip metadata must fail closed when unrated content is disabled"
        )
    }

    func test_clipItem_noRating_allowedWithPermissivePolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: nil)
        XCTAssertTrue(
            PlinxContentRules.isAllowed(item, policy: permissivePolicy),
            "Clip items should pass under permissive policy too"
        )
    }

    func test_clipItem_withRating_allowedWhenWithinPolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: "G")
        XCTAssertTrue(
            PlinxContentRules.isAllowed(item, policy: strictPolicy),
            "Clip items carrying a G rating must be allowed under a G-max policy"
        )
    }

    // MARK: - Movie items without rating

    func test_movieItem_noRating_blockedByStrictPolicy() {
        let item = MediaItem.fixture(type: .movie, contentRating: nil)
        XCTAssertFalse(
            PlinxContentRules.isAllowed(item, policy: strictPolicy),
            "Movie items without a rating must be blocked when allowUnrated=false"
        )
    }

    func test_movieItem_noRating_allowedByPermissivePolicy() {
        let item = MediaItem.fixture(type: .movie, contentRating: nil)
        XCTAssertTrue(
            PlinxContentRules.isAllowed(item, policy: permissivePolicy),
            "Movie items without a rating must be allowed when allowUnrated=true"
        )
    }

    // MARK: - Rating gate

    func test_movieItem_ratedG_allowed() {
        let item = MediaItem.fixture(type: .movie, contentRating: "G")
        XCTAssertTrue(PlinxContentRules.isAllowed(item, policy: strictPolicy))
    }

    func test_movieItem_ratedPG_blocked() {
        let item = MediaItem.fixture(type: .movie, contentRating: "PG")
        XCTAssertFalse(
            PlinxContentRules.isAllowed(item, policy: strictPolicy),
            "PG movie must be blocked by a G-max policy"
        )
    }

    func test_movieItem_ratedR_blocked() {
        let item = MediaItem.fixture(type: .movie, contentRating: "R")
        XCTAssertFalse(
            PlinxContentRules.isAllowed(item, policy: strictPolicy),
            "R-rated movie must be blocked by a G-max policy"
        )
        XCTAssertFalse(
            PlinxContentRules.isAllowed(item, policy: permissivePolicy),
            "Allowing unrated content must not lift the rating ceiling"
        )
    }

    // MARK: - Adult-only ratings are always rejected

    func test_adultOnlyRatings_blockedEvenByWidestPolicy() {
        for rating in ["NC-17", "X"] {
            let item = MediaItem.fixture(id: "adult-\(rating)", type: .movie, contentRating: rating)
            XCTAssertFalse(
                PlinxContentRules.isAllowed(item, policy: widestPolicy),
                "\(rating) must be rejected even with the highest ceilings and unrated content allowed"
            )
            XCTAssertFalse(
                PlinxContentRules.isAllowed(.playable(item), policy: widestPolicy),
                "\(rating) must be rejected when wrapped as a display item"
            )
        }
    }

    func test_hubWithOnlyAdultOnlyItems_isRemovedByWidestPolicy() {
        let adult = MediaItem.fixture(id: "adult", type: .movie, contentRating: "NC-17")
        let hub = Hub(id: "hub.movie.adult", title: "Adult", items: [.playable(adult)])
        XCTAssertNil(
            PlinxContentRules.filtered(hub, policy: widestPolicy),
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

        XCTAssertTrue(PlinxContentRules.isAllowed(tvY, policy: strictPolicy))
        XCTAssertFalse(PlinxContentRules.isAllowed(tvPG, policy: strictPolicy))
        XCTAssertTrue(PlinxContentRules.isAllowed(tvPG, policy: raisedPolicy))
    }

    func test_globalUnratedToggle_appliesToYouTubeLikeClips() {
        let unrated = MediaItem.fixture(id: "unrated-youtube", type: .clip, contentRating: nil)

        XCTAssertFalse(PlinxContentRules.isAllowed(unrated, policy: strictPolicy))
        XCTAssertTrue(PlinxContentRules.isAllowed(unrated, policy: permissivePolicy))
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
            PlinxContentRules.isAllowed(displayItem, policy: strictPolicy),
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
            PlinxContentRules.isAllowed(displayItem, policy: strictPolicy),
            "Playlists must always pass safety filtering (entries are filtered individually)"
        )
    }

    // MARK: - Hub-level filtering

    func test_hubWithUnratedClipItems_isRemovedByStrictFilter() throws {
        let clipItem = MediaItem.fixture(type: .clip, contentRating: nil)
        let hub = Hub(id: "hub.clip.recent", title: "Other Videos", items: [.playable(clipItem)])
        let filtered = PlinxContentRules.filtered(hub, policy: strictPolicy)
        XCTAssertNil(
            filtered,
            "An unrated clip hub must be removed when the parent has not enabled unrated content"
        )
    }

    func test_hubWithMovieNoRating_removedByStrictFilter() throws {
        let movieItem = MediaItem.fixture(type: .movie, contentRating: nil)
        let hub = Hub(id: "hub.movie.new", title: "New Movies", items: [.playable(movieItem)])
        let filtered = PlinxContentRules.filtered(hub, policy: strictPolicy)
        XCTAssertNil(
            filtered,
            "A hub containing only unrated movie items must be nil after strict safety filtering"
        )
    }

    func test_hubFilteringKeepsOnlyAllowedItemsAndRecountsSize() throws {
        let allowed = MediaItem.fixture(id: "allowed", type: .movie, contentRating: "G")
        let blocked = MediaItem.fixture(id: "blocked", type: .movie, contentRating: "R")
        let hub = Hub(id: "hub.movie.mixed", title: "Mixed", items: [.playable(blocked), .playable(allowed)])

        let filtered = try XCTUnwrap(PlinxContentRules.filtered(hub, policy: strictPolicy))

        XCTAssertEqual(filtered.items.map(\.id), ["allowed"])
        XCTAssertEqual(filtered.size, 1)
    }

    // MARK: - Playlist Play / Shuffle selection

    func test_playlistSelectionBuildsQueueOnlyFromAuthorizedEntries() {
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

        let authorized = PlinxPlaylistPlaybackSelection.authorizedItems(
            from: source,
            policy: strictPolicy
        )

        XCTAssertEqual(authorized.map(\.id), ["allowed"])
        XCTAssertEqual(
            PlinxPlaylistPlaybackSelection.item(
                from: source,
                policy: strictPolicy,
                shuffled: false
            )?.id,
            "allowed"
        )
        XCTAssertEqual(
            PlinxPlaylistPlaybackSelection.item(
                from: source,
                policy: strictPolicy,
                shuffled: true
            )?.id,
            "allowed",
            "Shuffle must only pick from authorized entries"
        )
    }

    func test_playlistSelectionReturnsNothingWhenNoEntryIsAuthorized() {
        let source: [MediaDisplayItem] = [
            .playable(MediaItem.fixture(id: "blocked", type: .movie, contentRating: "R")),
            .playable(MediaItem.fixture(id: "adult", type: .movie, contentRating: "X")),
            .playable(MediaItem.fixture(id: "unrated", type: .clip, contentRating: nil))
        ]

        XCTAssertTrue(PlinxPlaylistPlaybackSelection.authorizedItems(from: source, policy: strictPolicy).isEmpty)
        XCTAssertNil(PlinxPlaylistPlaybackSelection.item(from: source, policy: strictPolicy, shuffled: false))
        XCTAssertNil(PlinxPlaylistPlaybackSelection.item(from: source, policy: strictPolicy, shuffled: true))
    }
}

// MARK: - MediaItem test fixtures

private extension ServerIdentity {
    static let safetyTestServer = ServerIdentity(provider: .plex, id: "safety-test-server")
}

private extension MediaItem {
    /// Convenience initialiser for test fixtures.
    /// Only requires the fields that meaningfully vary between tests.
    static func fixture(
        id: String = "fixture-id",
        type: MediaKind = .movie,
        contentRating: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: .safetyTestServer, itemID: id),
            guid: "plex://\(type.rawValue)/\(id)",
            summary: nil,
            title: "Test Item",
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
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
