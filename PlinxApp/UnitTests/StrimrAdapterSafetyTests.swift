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
//   A prior regression caused clip-type content (Other Videos, YouTube, personal
//   home videos) to be hidden on the home page when the "Exclude Unrated"
//   setting was enabled. Clip items typically carry no MPAA/TV rating, so they
//   were caught by the unrated gate and filtered out entirely. These tests pin
//   the behaviour: clip-type content must ALWAYS pass through, regardless of
//   the allowUnrated flag, because personal home videos are unrated by nature
//   — they are not "unrated adult content".
//
//   Quick-reference regression table:
//   ┌─────────────────────────────────┬───────────────────┬────────────────┐
//   │ Item                            │ allowUnrated=false │ allowUnrated=true│
//   ├─────────────────────────────────┼───────────────────┼────────────────┤
//   │ Clip, no contentRating          │ ✅ allowed (fixed) │ ✅ allowed     │
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

    /// Default kid-safe policy; excludes unrated non-clip content.
    private let strictPolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)

    /// Permissive policy; allows all unrated content (used for contrast).
    private let permissivePolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: true)

    // MARK: - Clip items: always allowed regardless of allowUnrated

    func test_clipItem_noRating_allowedWithStrictPolicy() {
        let item = MediaItem.fixture(type: .clip, contentRating: nil)
        XCTAssertTrue(
            StrimrAdapter.isAllowed(item, policy: strictPolicy),
            "Clip items without a content rating must always pass — they are personal home videos, not unrated adult content"
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

    // MARK: - Collections / playlists: always allowed

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

    // MARK: - Hub-level filtering: clip hubs survive ExcludeUnrated=true

    func test_hubWithClipItems_survivesStrictFilter() throws {
        let clipItem = MediaItem.fixture(type: .clip, contentRating: nil)
        let hub = Hub(id: "hub.clip.recent", title: "Other Videos", items: [.playable(clipItem)])
        let filtered = StrimrAdapter.filtered(hub, policy: strictPolicy)
        XCTAssertNotNil(
            filtered,
            "A hub containing only clip items must NOT be removed by the safety filter when allowUnrated=false"
        )
        XCTAssertEqual(filtered?.items.count, 1, "The clip item must survive filtering")
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
