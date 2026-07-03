#if os(tvOS)
import XCTest
@testable import Plinx

final class AppleTVOtherVideoArtworkPolicyTests: XCTestCase {
    func test_otherVideoLibraries_useLandscapeThumbsAcrossDetailSurfaces() {
        let clipLibrary = Library(id: "3", title: "Other Videos", type: .clip, sectionId: 3)
        let noneAgentMovieLibrary = Library(
            id: "6",
            title: "YouTube Videos",
            type: .movie,
            sectionId: 6,
            agent: "tv.plex.agents.none"
        )

        assertOtherVideoLibraryPolicy(clipLibrary)
        assertOtherVideoLibraryPolicy(noneAgentMovieLibrary)
    }

    func test_standardMovieAndShowLibraries_keepPosterDetailCards() {
        let movieLibrary = Library(id: "1", title: "Movies", type: .movie, sectionId: 1)
        let showLibrary = Library(id: "2", title: "Shows", type: .show, sectionId: 2)

        assertStandardLibraryPolicy(movieLibrary)
        assertStandardLibraryPolicy(showLibrary)
    }

    private func assertOtherVideoLibraryPolicy(
        _ library: Library,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for surface in LibraryCardLayoutPolicy.DetailSurface.allCases {
            XCTAssertTrue(
                LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: surface),
                "\(library.title) must use landscape cards on \(surface)",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library),
            .thumb,
            "\(library.title) landscape cards must use thumbnails",
            file: file,
            line: line
        )
    }

    private func assertStandardLibraryPolicy(
        _ library: Library,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for surface in LibraryCardLayoutPolicy.DetailSurface.allCases {
            XCTAssertFalse(
                LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: surface),
                "\(library.title) must keep poster cards on \(surface)",
                file: file,
                line: line
            )
        }
        XCTAssertNil(
            ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library),
            "\(library.title) should not override landscape artwork",
            file: file,
            line: line
        )
    }
}
#endif
