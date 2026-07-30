import XCTest
@testable import Plinx

final class LibraryCardLayoutPolicyTests: XCTestCase {

    func test_movieLibrary_prefersPortrait() {
        let library = Library(id: "1", title: "Movies", type: .movie, sectionId: 1)
        XCTAssertFalse(LibraryCardLayoutPolicy.prefersLandscape(for: library))
    }

    func test_clipLibrary_prefersLandscape() {
        let library = Library(id: "3", title: "Other Videos", type: .clip, sectionId: 3)
        XCTAssertTrue(LibraryCardLayoutPolicy.prefersLandscape(for: library))
    }

    func test_noneAgentMovieLibrary_prefersLandscape() {
        let library = Library(
            id: "6",
            title: "Youtube Videos",
            type: .movie,
            sectionId: 6,
            agent: "tv.plex.agents.none"
        )
        XCTAssertTrue(LibraryCardLayoutPolicy.prefersLandscape(for: library))
    }

    func test_clipLibrary_usesLandscapeAcrossAllDetailSurfaces() {
        let library = Library(id: "3", title: "Other Videos", type: .clip, sectionId: 3)

        assertDetailSurfaces(for: library, useLandscape: true)
    }

    func test_noneAgentMovieLibrary_usesLandscapeAcrossAllDetailSurfaces() {
        let library = Library(
            id: "6",
            title: "Youtube Videos",
            type: .movie,
            sectionId: 6,
            agent: "tv.plex.agents.none"
        )

        assertDetailSurfaces(for: library, useLandscape: true)
    }

    func test_movieAndShowLibraries_usePortraitAcrossAllDetailSurfaces() {
        let movieLibrary = Library(id: "1", title: "Movies", type: .movie, sectionId: 1)
        let showLibrary = Library(id: "2", title: "Shows", type: .show, sectionId: 2)

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
