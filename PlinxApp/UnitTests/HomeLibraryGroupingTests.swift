// ─────────────────────────────────────────────────────────────────────────────
// HomeLibraryGroupingTests.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// Unit tests for HomeLibraryGrouping — the hub→library matching algorithm that
// drives the "Recently Added" row separation on the Plinx home screen.
//
// Running:
//   Select the Plinx-iOS-UnitTests target in Xcode and press Cmd+U.
//   (Requires re-running `xcodegen generate` in PlinxApp/ if it's not yet
//    visible in the project navigator.)
//
// Why these tests exist:
//   Mis-categorising an "Other Videos" (clip-type) library as a movie/TV
//   library caused all recently-added content to collapse into a single row.
//   These tests pin the three-priority matching algorithm so regressions are
//   caught immediately without a live Plex server.
// ─────────────────────────────────────────────────────────────────────────────

import XCTest
@testable import Plinx

final class HomeLibraryGroupingTests: XCTestCase {

    // MARK: - Fixtures

    private let movieLibrary  = Library(id: "1", title: "Movies",      type: .movie, sectionId: 1)
    private let showLibrary   = Library(id: "2", title: "TV Shows",    type: .show,  sectionId: 2)
    private let clipLibrary   = Library(id: "3", title: "Home Videos", type: .clip,  sectionId: 3)
    private let prefix        = "Recently Added"

    private var allLibraries: [Library] { [movieLibrary, showLibrary, clipLibrary] }

    // MARK: - Priority 1: Section-ID matching

    func test_sectionId_matchesMovieHub() {
        let hub = Hub(id: "hub.home.recentlyadded.1", title: "Recently Added Movies", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.type, .movie)
    }

    func test_sectionId_matchesShowHub() {
        let hub = Hub(id: "hub.home.recentlyadded.2", title: "Recently Added TV Shows", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.type, .show)
    }

    func test_sectionId_matchesClipHub() {
        let hub = Hub(id: "hub.home.recentlyadded.3", title: "Recently Added Home Videos", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.type, .clip,
            "Clip library must be matched via section ID — must NOT be merged into movies+TV row")
    }

    func test_sectionId_matchesHubWithTypeSuffix() {
        // Some Plex versions append "::movie" to the hub identifier.
        let hub = Hub(id: "hub.home.recentlyadded.1::movie", title: "Recently Added", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.type, .movie)
    }

    func test_sectionId_doesNotFalsePositiveOnPartialDigit() {
        // sectionId=1 must NOT match hub IDs that contain "1" as part of a longer number.
        // e.g. hub id "hub.home.recentlyadded.11" must NOT match sectionId=1.
        let hub = Hub(id: "hub.home.recentlyadded.11", title: "Some Other Hub", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertNil(matched, "Partial digit match must not occur (sectionId=1 must not match '11')")
    }

    // MARK: - Priority 2: Title-based matching

    func test_titleMatch_exactMatchAfterPrefixStrip() {
        // Hub titled "Recently Added Movies" → strip prefix → "Movies" → exact-match movieLibrary
        let hub = Hub(id: "hub.unknown.xyz", title: "Recently Added Movies", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.id, movieLibrary.id)
    }

    func test_titleMatch_caseInsensitiveExactMatch() {
        let hub = Hub(id: "hub.unknown", title: "recently added tv shows", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.id, showLibrary.id)
    }

    // MARK: - Priority 3: Type-keyword fallback

    func test_keywordFallback_movieKeywordMatchesMovieLibrary() {
        let hub = Hub(id: "promo.movie.hub", title: "Featured Films", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.type, .movie)
    }

    func test_keywordFallback_tvKeywordMatchesShowLibrary() {
        let hub = Hub(id: "promo.tv.hub", title: "Top Shows", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.type, .show)
    }

    func test_keywordFallback_clipKeywordMatchesClipLibrary() {
        let hub = Hub(id: "promo.clip.recent", title: "New Videos", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: hub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertEqual(matched?.type, .clip,
            "A 'clip' keyword in the hub ID must match the clip library, NOT fall through to movie")
    }

    // MARK: - Critical regression: clip must NEVER be classified as movie/show

    func test_clipLibraryHub_isNeverMergedIntoMoviesOrTVRow() {
        // Simulate the exact scenario that caused all libraries to merge:
        // A home-videos hub whose ID has no clear type signal and whose title
        // is ambiguous (Plex returns "Recently Added" for combined libraries).
        let ambiguousHub = Hub(id: "hub.home.recentlyadded.3", title: "Recently Added", items: [])
        let matched = HomeLibraryGrouping.matchLibrary(for: ambiguousHub, in: allLibraries, recentlyAddedPrefix: prefix)
        XCTAssertFalse(
            HomeLibraryGrouping.isMoviesOrTV(matched),
            "An Other-Videos (clip) library hub must never be classified as movie or TV"
        )
        XCTAssertTrue(
            HomeLibraryGrouping.isOtherVideo(matched),
            "An Other-Videos (clip) library hub must always land in the otherVideos section"
        )
    }

    // MARK: - isOtherVideo / isMoviesOrTV helpers

    func test_isMoviesOrTV_movieLibrary() {
        XCTAssertTrue(HomeLibraryGrouping.isMoviesOrTV(movieLibrary))
    }

    func test_isMoviesOrTV_showLibrary() {
        XCTAssertTrue(HomeLibraryGrouping.isMoviesOrTV(showLibrary))
    }

    func test_isMoviesOrTV_clipLibrary() {
        XCTAssertFalse(HomeLibraryGrouping.isMoviesOrTV(clipLibrary))
    }

    func test_isOtherVideo_nilLibrary() {
        // Unmatched libraries should be treated as "other video" (safe default).
        XCTAssertTrue(HomeLibraryGrouping.isOtherVideo(nil))
    }

    func test_isOtherVideo_clipLibrary() {
        XCTAssertTrue(HomeLibraryGrouping.isOtherVideo(clipLibrary))
    }
}
