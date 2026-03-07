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

    func test_bannerArtworkDisplayCount_usesThreeForPhonePortrait() {
        XCTAssertEqual(
            LibraryCardLayoutPolicy.bannerArtworkDisplayCount(isPhonePortrait: true),
            3
        )
    }

    func test_bannerArtworkDisplayCount_usesFiveOtherwise() {
        XCTAssertEqual(
            LibraryCardLayoutPolicy.bannerArtworkDisplayCount(isPhonePortrait: false),
            5
        )
    }
}
