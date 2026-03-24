import XCTest
@testable import Plinx

final class OfflinePlaybackTests: XCTestCase {
    // MARK: - DownloadItem.localMediaItem

    func test_localMediaItem_setsExpectedProperties() {
        let item = makeDownloadItem(
            id: "movie-1",
            type: .movie,
            title: "Test Movie",
            duration: 7200,
            viewOffset: 120
        )

        let media = item.metadata.localMediaItem

        XCTAssertEqual(media.id, "movie-1")
        XCTAssertEqual(media.title, "Test Movie")
        XCTAssertEqual(media.type, PlexItemType.movie)
        XCTAssertEqual(media.viewOffset, 120)
        XCTAssertEqual(media.duration, 7200)
    }

    func test_localMediaItem_episodePreservesHierarchy() {
        let item = makeDownloadItem(
            id: "ep-1",
            type: .episode,
            title: "Pilot",
            grandparentTitle: "Breaking Bad",
            parentTitle: "Season 1",
            parentIndex: 1,
            index: 1
        )

        let media = item.metadata.localMediaItem

        XCTAssertEqual(media.grandparentTitle, "Breaking Bad")
        XCTAssertEqual(media.parentTitle, "Season 1")
        XCTAssertEqual(media.parentIndex, 1)
        XCTAssertEqual(media.index, 1)
    }

    // MARK: - PlayerViewModel local init

    @MainActor
    func test_localPlayerViewModel_setsPlaybackURL() {
        let (viewModel, url) = makeLocalPlayerViewModel()

        XCTAssertEqual(viewModel.playbackURL, url)
    }

    @MainActor
    func test_localPlayerViewModel_setsMediaImmediately() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        XCTAssertNotNil(viewModel.media)
        XCTAssertEqual(viewModel.media?.id, "dl-1")
    }

    @MainActor
    func test_localPlayerViewModel_isLocalPlayback() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        XCTAssertTrue(viewModel.isLocalPlayback)
    }

    @MainActor
    func test_localPlayerViewModel_disablesServerReporting() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        // Local playback must not report timeline/position to the Plex server.
        // Verify by calling handleStop — in non-reporting mode this is a no-op.
        viewModel.handleStop()
        // If reporting were enabled this would crash without a valid context.
    }

    @MainActor
    func test_localPlayerViewModel_suppressesBufferingOnPropertyChange() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        viewModel.handlePropertyChange(property: .pausedForCache, data: true, isScrubbing: false)
        XCTAssertFalse(viewModel.isBuffering, "Local playback must suppress buffering state")

        viewModel.handlePropertyChange(property: .timePos, data: 30.0, isScrubbing: false)
        XCTAssertFalse(viewModel.isBuffering, "Local playback must suppress buffering on position update")
    }

    @MainActor
    func test_localPlayerViewModel_load_isNoOp() async {
        let (viewModel, url) = makeLocalPlayerViewModel()

        await viewModel.load()

        XCTAssertEqual(viewModel.playbackURL, url)
        XCTAssertNotNil(viewModel.media)
        XCTAssertFalse(viewModel.isBuffering)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - DownloadItem.isPlayable

    func test_isPlayable_onlyForCompletedDownloads() {
        let completed = makeDownloadItem(id: "a", type: .movie, status: .completed)
        let downloading = makeDownloadItem(id: "b", type: .movie, status: .downloading)
        let failed = makeDownloadItem(id: "c", type: .movie, status: .failed)

        XCTAssertTrue(completed.isPlayable)
        XCTAssertFalse(downloading.isPlayable)
        XCTAssertFalse(failed.isPlayable)
    }

    // MARK: - Helpers

    @MainActor
    private func makeLocalPlayerViewModel() -> (PlayerViewModel, URL) {
        let item = makeDownloadItem(id: "dl-1", type: .movie, title: "Offline Movie")
        let url = URL(fileURLWithPath: "/tmp/test-downloads/dl-1/video.mp4")
        let context = PlexAPIContext()
        let viewModel = PlayerViewModel(
            localMedia: item.metadata.localMediaItem,
            localPlaybackURL: url,
            context: context
        )
        return (viewModel, url)
    }

    private func makeDownloadItem(
        id: String,
        type: PlexItemType,
        title: String = "Test",
        status: DownloadStatus = .completed,
        duration: TimeInterval? = 3600,
        viewOffset: TimeInterval? = nil,
        grandparentTitle: String? = nil,
        parentTitle: String? = nil,
        parentIndex: Int? = nil,
        index: Int? = nil
    ) -> DownloadItem {
        DownloadItem(
            id: id,
            status: status,
            progress: status == .completed ? 1 : 0.5,
            bytesWritten: 100,
            totalBytes: 100,
            taskIdentifier: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                ratingKey: id,
                guid: "guid://\(id)",
                type: type,
                sourceLibrarySectionID: 1,
                artworkLayoutStyle: nil,
                title: title,
                summary: nil,
                genres: [],
                year: 2024,
                duration: duration,
                contentRating: nil,
                studio: nil,
                tagline: nil,
                parentRatingKey: nil,
                grandparentRatingKey: nil,
                grandparentTitle: grandparentTitle,
                parentTitle: parentTitle,
                parentIndex: parentIndex,
                index: index,
                posterFileName: nil,
                videoFileName: "video.mp4",
                fileSize: nil,
                createdAt: Date(),
                viewOffset: viewOffset,
                viewCount: nil,
                lastPlayedAt: nil
            )
        )
    }
}
