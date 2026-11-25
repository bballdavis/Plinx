import XCTest
@testable import Plinx

final class DownloadsArtworkLayoutPolicyTests: XCTestCase {
    func test_portraitLayoutAlwaysUsesPosterRatio() {
        let ratio = DownloadsArtworkLayoutPolicy.displayAspectRatio(
            for: .portrait,
            imageSize: CGSize(width: 720, height: 405)
        )

        XCTAssertEqual(ratio, DownloadsArtworkLayoutPolicy.portraitAspectRatio, accuracy: 0.0001)
    }

    func test_clipPortraitSourceStillRendersLandscape() {
        let ratio = DownloadsArtworkLayoutPolicy.displayAspectRatio(
            for: .landscape,
            imageSize: CGSize(width: 480, height: 720)
        )

        XCTAssertGreaterThanOrEqual(ratio, DownloadsArtworkLayoutPolicy.minimumLandscapeAspectRatio)
    }

    func test_clipWideSourcePreservesWideRatio() {
        let ratio = DownloadsArtworkLayoutPolicy.displayAspectRatio(
            for: .landscape,
            imageSize: CGSize(width: 720, height: 405)
        )

        XCTAssertEqual(ratio, 720.0 / 405.0, accuracy: 0.0001)
    }

    func test_movieCanOptIntoLandscapeLayout() {
        var metadata = DownloadedMediaMetadata(
            identity: MediaIdentity(
                server: ServerIdentity(provider: .plex, id: "server-1"),
                itemID: "movie-1"
            ),
            guid: "guid://movie-1",
            type: .movie,
            title: "Movie",
            summary: nil,
            genres: [],
            year: 2025,
            duration: nil,
            viewCount: nil,
            contentRating: nil,
            studio: nil,
            tagline: nil,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            posterFileName: nil,
            videoFileName: "video",
            fileSize: nil,
            requestedQuality: .original,
            effectiveQuality: .original,
            audioTitle: nil,
            subtitleTitle: nil,
            createdAt: Date()
        )

        XCTAssertTrue(metadata.prefersPortraitArtwork)
        XCTAssertEqual(metadata.resolvedArtworkLayoutStyle, .portrait)

        metadata.artworkLayoutStyle = .landscape

        XCTAssertFalse(metadata.prefersPortraitArtwork)
        XCTAssertEqual(metadata.resolvedArtworkLayoutStyle, .landscape)
    }

    func test_downloadUiFixturesIncludeEnoughMixedItemsForTwoRows() {
        let items = DownloadUITestFixtures.makeItems(seed: 17)

        XCTAssertGreaterThanOrEqual(items.count, 8)
        XCTAssertTrue(items.contains(where: { $0.metadata.type == .movie }))
        XCTAssertTrue(items.contains(where: { $0.metadata.type == .episode }))
        XCTAssertTrue(items.contains(where: { $0.metadata.type == .clip }))
        XCTAssertTrue(items.allSatisfy { $0.status == .downloading })
    }
}