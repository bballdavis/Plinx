import XCTest
@testable import Plinx

final class OfflineContentBuilderTests: XCTestCase {
    func test_buildSnapshot_createsContinueWatchingAndOtherVideosSections() {
        let snapshot = OfflineContentBuilder.buildSnapshot(
            downloadItems: [
                makeDownloadItem(
                    id: "movie-1",
                    type: .movie,
                    sectionId: 1,
                    createdAt: Date(timeIntervalSince1970: 200),
                    viewOffset: 120,
                    lastPlayedAt: Date(timeIntervalSince1970: 500)
                ),
                makeDownloadItem(
                    id: "clip-1",
                    type: .movie,
                    sectionId: 6,
                    createdAt: Date(timeIntervalSince1970: 400),
                    artworkLayoutStyle: .landscape
                )
            ],
            libraries: [
                Library(id: "1", title: "Movies", type: .movie, sectionId: 1, agent: "tv.plex.agents.movie"),
                Library(id: "6", title: "Youtube Videos", type: .movie, sectionId: 6, agent: "tv.plex.agents.none")
            ],
            policy: .ratingOnly(allowUnrated: true)
        )

        XCTAssertEqual(snapshot.homeSections.first?.id, "continueWatching")
        XCTAssertTrue(snapshot.homeSections.contains(where: { $0.title == "Youtube Videos" }))
        XCTAssertEqual(snapshot.libraries.count, 2)
    }

    func test_buildSnapshot_filtersCompletedDownloadsOnly() {
        let snapshot = OfflineContentBuilder.buildSnapshot(
            downloadItems: [
                makeDownloadItem(id: "movie-1", type: .movie, status: .completed),
                makeDownloadItem(id: "movie-2", type: .movie, status: .downloading)
            ],
            libraries: [Library(id: "1", title: "Movies", type: .movie, sectionId: 1)],
            policy: .ratingOnly(allowUnrated: true)
        )

        XCTAssertEqual(snapshot.libraries.first?.items.count, 1)
        XCTAssertEqual(snapshot.libraries.first?.items.first?.id, "movie-1")
    }

    private func makeDownloadItem(
        id: String,
        type: PlexItemType,
        sectionId: Int? = 1,
        status: DownloadStatus = .completed,
        createdAt: Date = Date(timeIntervalSince1970: 100),
        artworkLayoutStyle: DownloadArtworkLayoutStyle? = nil,
        viewOffset: TimeInterval? = nil,
        lastPlayedAt: Date? = nil
    ) -> DownloadItem {
        DownloadItem(
            id: id,
            status: status,
            progress: 1,
            bytesWritten: 100,
            totalBytes: 100,
            taskIdentifier: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                ratingKey: id,
                guid: "guid://\(id)",
                type: type,
                sourceLibrarySectionID: sectionId,
                artworkLayoutStyle: artworkLayoutStyle,
                title: id,
                summary: nil,
                genres: [],
                year: 2024,
                duration: 1_000,
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
                createdAt: createdAt,
                viewOffset: viewOffset,
                viewCount: nil,
                lastPlayedAt: lastPlayedAt
            )
        )
    }
}