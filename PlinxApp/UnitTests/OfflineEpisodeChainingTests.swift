@testable import Plinx
import PlinxCore
import XCTest

/// Offline next-episode chaining (`PlayerViewModel.chainedLocalPlaybackRequest`) makes the same access decision as
/// the downloads grid, the detail page and the launcher (`DownloadAccessPolicy`): the next downloaded episode plays
/// only when it belongs to the active profile and both the metadata stored with it and the server metadata pinned for
/// it pass the gate. A blocked episode ends the chain before anything of it is built.
@MainActor
final class OfflineEpisodeChainingTests: XCTestCase {
    private let server = ServerIdentity(provider: .plex, id: "server-a")
    private lazy var owner = MediaOwner(server: server, userID: "profile-a")
    private lazy var otherOwner = MediaOwner(server: server, userID: "profile-b")
    /// The parent's ceiling: TV-PG television, no unrated content.
    private lazy var gate = ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false))

    func test_allowedNextEpisodeChains() {
        let next = makeEpisode(id: "ep-2", contentRating: "TV-G", ownerID: owner.id)
        var built: [String] = []

        let request = PlayerViewModel.chainedLocalPlaybackRequest(
            next: next,
            policy: policy(pinned: next.localMediaItem),
            playbackRequest: { item in
                built.append(item.id)
                return makeRequest(for: item, media: item.localMediaItem)
            },
        )

        XCTAssertEqual(request?.media.id, "ep-2")
        XCTAssertEqual(built, ["ep-2"])
    }

    /// The downloads grid hides a row stored without a rating (for example a pre-fork download) while unrated
    /// content is off, even when the server metadata pinned for it is rated. Chaining used to check only the pinned
    /// record, so the hidden episode could still play next.
    func test_nextEpisodeWhoseStoredMetadataFailsDoesNotChainEvenWhenPinnedMetadataPasses() {
        let next = makeEpisode(id: "ep-2", contentRating: nil, ownerID: owner.id)
        var pinnedMetadata = next.metadata
        pinnedMetadata.contentRating = "TV-G"
        let pinned = pinnedMetadata.localMediaItem
        XCTAssertTrue(gate.isAllowed(pinned), "The pinned record alone passes the gate")
        var built: [String] = []

        let request = PlayerViewModel.chainedLocalPlaybackRequest(
            next: next,
            policy: policy(pinned: pinned),
            playbackRequest: { item in
                built.append(item.id)
                return makeRequest(for: item, media: pinned)
            },
        )

        XCTAssertNil(request)
        XCTAssertTrue(built.isEmpty, "Nothing of a blocked episode is built")
    }

    func test_nextEpisodeWhosePinnedMetadataFailsDoesNotChain() {
        let next = makeEpisode(id: "ep-2", contentRating: "TV-G", ownerID: owner.id)
        var reRated = next.metadata
        reRated.contentRating = "TV-14"

        let request = PlayerViewModel.chainedLocalPlaybackRequest(
            next: next,
            policy: policy(pinned: reRated.localMediaItem),
            playbackRequest: { item in makeRequest(for: item, media: reRated.localMediaItem) },
        )

        XCTAssertNil(request)
    }

    func test_nextEpisodeOfAnotherProfileOrWithoutOwnerDoesNotChain() {
        for ownerID in [otherOwner.id, nil] {
            let next = makeEpisode(id: "ep-2", contentRating: "TV-G", ownerID: ownerID)

            let request = PlayerViewModel.chainedLocalPlaybackRequest(
                next: next,
                policy: policy(pinned: next.localMediaItem),
                playbackRequest: { item in makeRequest(for: item, media: item.localMediaItem) },
            )

            XCTAssertNil(request, "owner \(ownerID ?? "none")")
        }
    }

    func test_noNextEpisodeEndsTheChain() {
        let request = PlayerViewModel.chainedLocalPlaybackRequest(
            next: nil,
            policy: policy(pinned: nil),
            playbackRequest: { _ in
                XCTFail("No playback is prepared without a next episode")
                return nil
            },
        )

        XCTAssertNil(request)
    }

    // MARK: - Helpers

    private func policy(pinned: MediaItem?) -> DownloadAccessPolicy {
        DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: gate, pinnedMedia: { _ in pinned })
    }

    private func makeRequest(for item: DownloadItem, media: MediaItem) -> LocalPlaybackRequest {
        LocalPlaybackRequest(
            media: media,
            url: URL(fileURLWithPath: "/tmp/test-downloads/\(item.id)/video.mp4"),
            externalSubtitles: [],
            owner: owner,
            resumes: false,
        )
    }

    private func makeEpisode(id: String, contentRating: String?, ownerID: String?) -> DownloadItem {
        DownloadItem(
            id: id,
            status: .completed,
            progress: 1,
            bytesWritten: 100,
            totalBytes: 100,
            taskIdentifier: nil,
            remoteReference: nil,
            trackPreference: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                identity: MediaIdentity(server: server, itemID: id),
                guid: "guid://\(id)",
                type: .episode,
                title: "Episode",
                summary: nil,
                genres: [],
                year: 2024,
                duration: 1200,
                viewCount: nil,
                contentRating: contentRating,
                studio: nil,
                tagline: nil,
                parentRatingKey: "season-1",
                grandparentRatingKey: "series-1",
                grandparentTitle: "Series",
                parentTitle: "Season 1",
                parentIndex: 1,
                index: 2,
                posterFileName: nil,
                videoFileName: "video.mp4",
                fileSize: nil,
                requestedQuality: .original,
                effectiveQuality: .original,
                audioTitle: nil,
                subtitleTitle: nil,
                createdAt: Date(),
            ),
            ownerID: ownerID,
        )
    }
}
