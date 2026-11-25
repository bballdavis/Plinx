import XCTest
@testable import Plinx

final class LibraryCardLayoutPolicyTests: XCTestCase {
    private let server = ServerIdentity(provider: .plex, id: "layout-server")

    func test_movieLibrary_prefersPortrait() {
        let library = Library(id: "1", title: "Movies", type: .movie, sectionId: 1, server: server)
        XCTAssertFalse(LibraryCardLayoutPolicy.prefersLandscape(for: library))
    }

    func test_clipLibrary_prefersLandscape() {
        let library = Library(id: "3", title: "Other Videos", type: .clip, sectionId: 3, server: server)
        XCTAssertTrue(LibraryCardLayoutPolicy.prefersLandscape(for: library))
    }

    func test_noneAgentMovieLibrary_prefersLandscape() {
        let library = Library(
            id: "6",
            title: "Youtube Videos",
            type: .movie,
            sectionId: 6,
            agent: "tv.plex.agents.none",
            server: server
        )
        XCTAssertTrue(LibraryCardLayoutPolicy.prefersLandscape(for: library))
    }

    func test_clipLibrary_usesLandscapeAcrossAllDetailSurfaces() {
        let library = Library(id: "3", title: "Other Videos", type: .clip, sectionId: 3, server: server)

        assertDetailSurfaces(for: library, useLandscape: true)
    }

    func test_noneAgentMovieLibrary_usesLandscapeAcrossAllDetailSurfaces() {
        let library = Library(
            id: "6",
            title: "Youtube Videos",
            type: .movie,
            sectionId: 6,
            agent: "tv.plex.agents.none",
            server: server
        )

        assertDetailSurfaces(for: library, useLandscape: true)
    }

    func test_movieAndShowLibraries_usePortraitAcrossAllDetailSurfaces() {
        let movieLibrary = Library(id: "1", title: "Movies", type: .movie, sectionId: 1, server: server)
        let showLibrary = Library(id: "2", title: "Shows", type: .series, sectionId: 2, server: server)

        assertDetailSurfaces(for: movieLibrary, useLandscape: false)
        assertDetailSurfaces(for: showLibrary, useLandscape: false)
    }

    func test_defaultBannerArtworkDisplayCount_usesThreeForPhone() {
        XCTAssertEqual(
            LibraryCardLayoutPolicy.defaultBannerArtworkDisplayCount(userInterfaceIdiom: .phone),
            3
        )
    }

    func test_defaultBannerArtworkDisplayCount_usesFiveForPad() {
        XCTAssertEqual(
            LibraryCardLayoutPolicy.defaultBannerArtworkDisplayCount(userInterfaceIdiom: .pad),
            5
        )
    }

    func test_resolvedBannerArtworkDisplayCount_clampsToPhoneMaximum() {
        XCTAssertEqual(
            LibraryCardLayoutPolicy.resolvedBannerArtworkDisplayCount(storedCount: 5, userInterfaceIdiom: .phone),
            3
        )
    }

    func test_resolvedBannerArtworkDisplayCount_usesDeviceDefaultWhenUnset() {
        XCTAssertEqual(
            LibraryCardLayoutPolicy.resolvedBannerArtworkDisplayCount(storedCount: 0, userInterfaceIdiom: .pad),
            5
        )
    }

    // MARK: - Grid metrics

    func test_gridMetrics_iPhonePortraitPostersFillWidthInThreeColumns() {
        // 393pt iPhone minus 16pt padding on each side.
        let metrics = LibraryCardLayoutPolicy.gridMetrics(availableWidth: 361, usesLandscapeCards: false)

        XCTAssertEqual(metrics.columnCount, 3)
        XCTAssertEqual(metrics.cardWidth, 112)
        XCTAssertLessThanOrEqual(metrics.contentWidth, 361)
        XCTAssertLessThan(361 - metrics.contentWidth, CGFloat(metrics.columnCount))
    }

    func test_gridMetrics_narrowPhoneUsesWiderEvenlySpacedColumns() {
        let metrics = LibraryCardLayoutPolicy.gridMetrics(availableWidth: 288, usesLandscapeCards: false)

        XCTAssertEqual(metrics.columnCount, 2)
        XCTAssertEqual(metrics.cardWidth, 138)
        XCTAssertEqual(metrics.contentWidth, 288)
    }

    func test_gridMetrics_landscapeThumbnailsUseTwoColumnsOnPhone() {
        let metrics = LibraryCardLayoutPolicy.gridMetrics(availableWidth: 361, usesLandscapeCards: true)

        XCTAssertEqual(metrics.columnCount, 2)
        XCTAssertEqual(metrics.cardWidth, 174)
        XCTAssertLessThanOrEqual(metrics.contentWidth, 361)
    }

    func test_gridMetrics_iPadAddsColumnsInsteadOfOversizedCards() {
        let posters = LibraryCardLayoutPolicy.gridMetrics(availableWidth: 788, usesLandscapeCards: false)
        let thumbnails = LibraryCardLayoutPolicy.gridMetrics(availableWidth: 788, usesLandscapeCards: true)

        XCTAssertEqual(posters.columnCount, 6)
        XCTAssertEqual(thumbnails.columnCount, 4)
        XCTAssertLessThanOrEqual(posters.contentWidth, 788)
        XCTAssertLessThanOrEqual(thumbnails.contentWidth, 788)
    }

    func test_gridMetrics_capsCardWidthAndLeavesSlackForCentering() {
        let metrics = LibraryCardLayoutPolicy.gridMetrics(availableWidth: 200, usesLandscapeCards: false)

        XCTAssertEqual(metrics.columnCount, 1)
        XCTAssertEqual(metrics.cardWidth, 180)
        XCTAssertEqual(metrics.contentWidth, 180)
    }

    func test_gridMetrics_degenerateWidthsStaySafe() {
        for width in [0, -10, CGFloat.nan, .infinity] {
            let metrics = LibraryCardLayoutPolicy.gridMetrics(availableWidth: width, usesLandscapeCards: false)
            XCTAssertEqual(metrics.columnCount, 1)
            XCTAssertGreaterThanOrEqual(metrics.cardWidth, 1)
        }
    }

    private func assertDetailSurfaces(
        for library: Library,
        useLandscape: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for surface in LibraryCardLayoutPolicy.DetailSurface.allCases {
            XCTAssertEqual(
                LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: surface),
                useLandscape,
                "\(library.title) should \(useLandscape ? "use" : "not use") landscape cards on \(surface)",
                file: file,
                line: line
            )
        }
    }
}
