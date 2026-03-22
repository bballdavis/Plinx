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
}
