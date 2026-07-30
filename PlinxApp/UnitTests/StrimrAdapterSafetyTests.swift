// ─────────────────────────────────────────────────────────────────────────────
// StrimrAdapterSafetyTests.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// Unit tests for StrimrAdapter — the safety bridge between Strimr media types
// and PlinxCore safety policies.
//
// Running:
//   Select the Plinx-iOS-UnitTests target in Xcode and press Cmd+U.
//
// Why these tests exist:
//   Every item follows the same parent-selected rating policy. Plex clips and
//   home videos commonly omit a rating, but that is not evidence that they are
//   allowed. They remain hidden until the parent explicitly enables unrated
//   content.
//
//   Quick-reference regression table:
//   ┌─────────────────────────────────┬───────────────────┬────────────────┐
//   │ Item                            │ allowUnrated=false │ allowUnrated=true│
//   ├─────────────────────────────────┼───────────────────┼────────────────┤
//   │ Clip, no contentRating          │ ❌ blocked         │ ✅ allowed     │
//   │ Movie, no contentRating         │ ❌ blocked         │ ✅ allowed     │
//   │ Movie, contentRating="R"        │ ❌ blocked (G max)  │ ❌ blocked     │
//   │ Movie, contentRating="G"        │ ✅ allowed         │ ✅ allowed     │
//   │ Collection                      │ ✅ always allowed  │ ✅ always allowed│
//   │ Playlist                        │ ✅ always allowed  │ ✅ always allowed│
//   └─────────────────────────────────┴───────────────────┴────────────────┘
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

    // MARK: - Clip items follow the same unrated policy

    func test_clipItem_noRating_blockedWithStrictPolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: nil)
        XCTAssertFalse(
            StrimrAdapter.isAllowed(item, policy: strictPolicy),
            "Missing clip metadata must fail closed when unrated content is disabled"
        )
    }

    func test_clipItem_noRating_allowedWithPermissivePolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: nil)
        XCTAssertTrue(
            StrimrAdapter.isAllowed(item, policy: permissivePolicy),
            "Clip items should pass under permissive policy too"
        )
    }

    func test_clipItem_withRating_allowedWhenWithinPolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: "G")
        XCTAssertTrue(
            StrimrAdapter.isAllowed(item, policy: strictPolicy),
            "Clip items carrying a G rating must be allowed under a G-max policy"
        )
    }

    // MARK: - Movie items without rating

    func test_movieItem_noRating_blockedByStrictPolicy() {
        let item = MediaItem.fixture(type: .movie, contentRating: nil)
        XCTAssertFalse(
            StrimrAdapter.isAllowed(item, policy: strictPolicy),
            "Movie items without a rating must be blocked when allowUnrated=false"
        )
    }

    func test_movieItem_noRating_allowedByPermissivePolicy() {
        let item = MediaItem.fixture(type: .movie, contentRating: nil)
        XCTAssertTrue(
            StrimrAdapter.isAllowed(item, policy: permissivePolicy),
            "Movie items without a rating must be allowed when allowUnrated=true"
        )
    }

    // MARK: - Rating gate

    func test_movieItem_ratedG_allowed() {
        let item = MediaItem.fixture(type: .movie, contentRating: "G")
        XCTAssertTrue(StrimrAdapter.isAllowed(item, policy: strictPolicy))
    }

    func test_movieItem_ratedPG_blocked() {
        let item = MediaItem.fixture(type: .movie, contentRating: "PG")
        XCTAssertFalse(
            StrimrAdapter.isAllowed(item, policy: strictPolicy),
            "PG movie must be blocked by a G-max policy"
        )
    }

    func test_movieItem_ratedR_blocked() {
        let item = MediaItem.fixture(type: .movie, contentRating: "R")
        XCTAssertFalse(
            StrimrAdapter.isAllowed(item, policy: strictPolicy),
            "R-rated movie must be blocked by a G-max policy"
        )
    }

    func test_globalTVRatingCeiling_appliesToYouTubeLikeClips() {
        let tvY = MediaItem.fixture(id: "tv-y", type: .clip, contentRating: "TV-Y")
        let tvPG = MediaItem.fixture(id: "tv-pg", type: .clip, contentRating: "TV-PG")
        let raisedPolicy = SafetyPolicy.ratingOnly(
            maxMovie: .g,
            maxTV: .tvPg,
            allowUnrated: false
        )

        XCTAssertTrue(PlinxContentAuthorization.isAllowed(tvY, policy: strictPolicy))
        XCTAssertFalse(PlinxContentAuthorization.isAllowed(tvPG, policy: strictPolicy))
        XCTAssertTrue(PlinxContentAuthorization.isAllowed(tvPG, policy: raisedPolicy))
    }

    func test_globalUnratedToggle_appliesToYouTubeLikeClips() {
        let unrated = MediaItem.fixture(id: "unrated-youtube", type: .clip, contentRating: nil)

        XCTAssertFalse(PlinxContentAuthorization.isAllowed(unrated, policy: strictPolicy))
        XCTAssertTrue(PlinxContentAuthorization.isAllowed(unrated, policy: permissivePolicy))
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
            maxYear: nil
        ))
        XCTAssertTrue(
            StrimrAdapter.isAllowed(displayItem, policy: strictPolicy),
            "Collections must always pass safety filtering (children are filtered individually)"
        )
    }

    // MARK: - Hub-level filtering

    func test_hubWithUnratedClipItems_isRemovedByStrictFilter() throws {
        let clipItem = MediaItem.fixture(type: .clip, contentRating: nil)
        let hub = Hub(id: "hub.clip.recent", title: "Other Videos", items: [.playable(clipItem)])
        let filtered = StrimrAdapter.filtered(hub, policy: strictPolicy)
        XCTAssertNil(
            filtered,
            "An unrated clip hub must be removed when the parent has not enabled unrated content"
        )
    }

    func test_hubWithMovieNoRating_removedByStrictFilter() throws {
        let movieItem = MediaItem.fixture(type: .movie, contentRating: nil)
        let hub = Hub(id: "hub.movie.new", title: "New Movies", items: [.playable(movieItem)])
        let filtered = StrimrAdapter.filtered(hub, policy: strictPolicy)
        XCTAssertNil(
            filtered,
            "A hub containing only unrated movie items must be nil after strict safety filtering"
        )
    }

    func test_playlistSelectionBuildsQueueOnlyFromAuthorizedEntries() {
        let allowed = MediaItem.fixture(id: "allowed", type: .movie, contentRating: "G")
        let blocked = MediaItem.fixture(id: "blocked", type: .movie, contentRating: "R")
        let unrated = MediaItem.fixture(id: "unrated", type: .clip, contentRating: nil)
        let source: [MediaDisplayItem] = [
            .playable(blocked),
            .playable(allowed),
            .playable(unrated)
        ]

        let authorized = SafePlaylistPlaybackSelection.authorizedItems(
            from: source,
            policy: strictPolicy
        )

        XCTAssertEqual(authorized.map(\.id), ["allowed"])
        XCTAssertEqual(
            SafePlaylistPlaybackSelection.item(
                from: source,
                policy: strictPolicy,
                shuffled: false
            )?.id,
            "allowed"
        )
    }
}

// MARK: - MediaItem test fixtures

private extension MediaItem {
    /// Convenience initialiser for test fixtures.
    /// Only requires the fields that meaningfully vary between tests.
    static func fixture(
        id: String = "fixture-id",
        type: PlexItemType = .movie,
        contentRating: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            guid: "plex://\(type)/\(id)",
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
            ultraBlurColors: nil,
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
