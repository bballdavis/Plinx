import XCTest
@testable import Plinx

final class DownloadsArtworkLayoutPolicyTests: XCTestCase {
    func test_portraitTypesAlwaysUsePosterRatio() {
        let ratio = DownloadsArtworkLayoutPolicy.displayAspectRatio(
            for: .movie,
            imageSize: CGSize(width: 720, height: 405)
        )

        XCTAssertEqual(ratio, DownloadsArtworkLayoutPolicy.portraitAspectRatio, accuracy: 0.0001)
    }

    func test_clipPortraitSourceStillRendersLandscape() {
        let ratio = DownloadsArtworkLayoutPolicy.displayAspectRatio(
            for: .clip,
            imageSize: CGSize(width: 480, height: 720)
        )

        XCTAssertGreaterThanOrEqual(ratio, DownloadsArtworkLayoutPolicy.minimumLandscapeAspectRatio)
    }

    func test_clipWideSourcePreservesWideRatio() {
        let ratio = DownloadsArtworkLayoutPolicy.displayAspectRatio(
            for: .clip,
            imageSize: CGSize(width: 720, height: 405)
        )

        XCTAssertEqual(ratio, 720.0 / 405.0, accuracy: 0.0001)
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