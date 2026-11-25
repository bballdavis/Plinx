@testable import Plinx
import PlinxCore
import XCTest

/// Offline playback of downloads: the media built from a download, the local player, what a tap on a download
/// does, and which downloads the active profile may see and play.
///
/// Ownership is the download's own `ownerID` (`MediaOwner`), and the active profile owns the downloads of the owners
/// `DownloadManager` activated for it; `DownloadAccessPolicy(activeOwnerIDs:gate:pinnedMedia:)` decides on that.
/// Pre-fork Plinx kept a separate `DownloadOwnershipStore` with enrollment, rollback and "grandfathered" downloads
/// shared with every profile. That store is gone: pre-fork owners are imported once by `LegacyDownloadOwnership`
/// (see `DownloadOwnershipMigrationTests`), and a download without an owner is parent-only, never shared.
@MainActor
final class OfflinePlaybackTests: XCTestCase {
    private let server = ServerIdentity(provider: .plex, id: "server-a")
    private lazy var owner = MediaOwner(server: server, userID: "profile-a")
    private lazy var otherOwner = MediaOwner(server: server, userID: "profile-b")

    // MARK: - DownloadItem.localMediaItem

    func test_localMediaItem_setsExpectedProperties() {
        let item = makeDownloadItem(
            id: "movie-1",
            type: .movie,
            title: "Test Movie",
            duration: 7200,
            contentRating: "PG"
        )

        let media = item.metadata.localMediaItem

        XCTAssertEqual(media.id, "movie-1")
        XCTAssertEqual(media.identity, MediaIdentity(server: server, itemID: "movie-1"))
        XCTAssertEqual(media.title, "Test Movie")
        XCTAssertEqual(media.type, MediaKind.movie)
        XCTAssertEqual(media.duration, 7200)
        // The gate judges a download on the rating stored with it.
        XCTAssertEqual(media.contentRating, "PG")
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

    func test_localMediaItem_withoutStoredServerNeverResolvesAgainstARealServer() {
        var item = makeDownloadItem(id: "legacy", type: .movie)
        item.metadata.identity = nil

        let media = item.localMediaItem

        XCTAssertEqual(media.id, "legacy")
        XCTAssertNotEqual(media.identity.server, server)
        XCTAssertTrue(media.identity.server.id.hasPrefix("legacy-download:"))
    }

    // MARK: - PlayerViewModel local init

    func test_localPlayerViewModel_setsPlaybackURL() {
        let (viewModel, url) = makeLocalPlayerViewModel()

        XCTAssertEqual(viewModel.playbackURL, url)
    }

    func test_localPlayerViewModel_setsMediaImmediately() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        XCTAssertNotNil(viewModel.media)
        XCTAssertEqual(viewModel.media?.id, "dl-1")
    }

    func test_localPlayerViewModel_isLocalPlayback() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        XCTAssertTrue(viewModel.isLocalPlayback)
    }

    func test_localPlayerViewModel_disablesServerReporting() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        // Local playback has no media services and never reports timeline/position to a server.
        // Without an owner there is no local progress recorder either, so handleStop is a no-op.
        viewModel.handleStop()
    }

    func test_localPlayerViewModel_suppressesBufferingFromAetherUpdates() {
        let (viewModel, _) = makeLocalPlayerViewModel()

        viewModel.handlePlaybackState(isPaused: false, isBuffering: true)
        XCTAssertFalse(viewModel.isBuffering, "Local playback must suppress buffering state")

        viewModel.handlePlaybackPosition(30, isScrubbing: false)
        XCTAssertFalse(viewModel.isBuffering, "Local playback must suppress buffering on position update")
    }

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

    // MARK: - Download tap actions

    func test_tapOnAllowedCompletedDownloadPlays() {
        let item = makeDownloadItem(id: "a", type: .movie, status: .completed)

        XCTAssertEqual(DownloadTapAction.resolve(for: item, decision: .allowed), .play)
    }

    func test_tapOnAllowedFailedDownloadOffersRemoveAndRedownload() {
        let item = makeDownloadItem(id: "a", type: .movie, status: .failed)

        XCTAssertEqual(DownloadTapAction.resolve(for: item, decision: .allowed), .showFailureActions)
    }

    func test_tapOnInProgressDownloadDoesNothing() {
        // Pre-fork `deciding` decodes as `preparing` (see `DownloadIntegrityTests`).
        for status in [DownloadStatus.queued, .preparing, .downloading] {
            let item = makeDownloadItem(id: "a", type: .movie, status: status)
            XCTAssertEqual(DownloadTapAction.resolve(for: item, decision: .allowed), .none, "\(status)")
        }
    }

    func test_tapOnDisallowedDownloadDoesNothingEvenWhenFailed() {
        let decisions: [DownloadAccessDecision] = [.blockedByContentPolicy, .wrongOwner, .missingOwner]
        for decision in decisions {
            for status in [DownloadStatus.completed, .failed] {
                let item = makeDownloadItem(id: "a", type: .movie, status: status)
                XCTAssertEqual(DownloadTapAction.resolve(for: item, decision: decision), .none)
            }
        }
    }

    // MARK: - Download access policy

    func test_downloadAccessRequiresMatchingOwnerAndCurrentPolicy() {
        let item = makeDownloadItem(id: "owned", type: .movie, contentRating: "PG", ownerID: owner.id)
        let policy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: pgGate())

        XCTAssertEqual(policy.decision(for: item), .allowed)
        XCTAssertEqual(DownloadTapAction.resolve(for: item, decision: policy.decision(for: item)), .play)
    }

    func test_downloadAccessHidesWrongOwnerAndNewlyDisallowedItem() {
        let item = makeDownloadItem(id: "restricted", type: .movie, contentRating: "R", ownerID: owner.id)
        let gate = ContentSafetyGate(policy: .ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: false))

        let wrongOwnerPolicy = DownloadAccessPolicy(activeOwnerIDs: [otherOwner.id], gate: gate)
        XCTAssertEqual(wrongOwnerPolicy.decision(for: item), .wrongOwner)

        let ownerPolicy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: gate)
        XCTAssertEqual(ownerPolicy.decision(for: item), .allowed)

        // A parent lowers the ceiling: the download saved under the looser one disappears.
        let revisionBefore = gate.revision
        gate.policy = .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)

        XCTAssertGreaterThan(gate.revision, revisionBefore)
        XCTAssertEqual(ownerPolicy.decision(for: item), .blockedByContentPolicy)
        let newlyRestrictedPolicy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: gate)
        XCTAssertEqual(newlyRestrictedPolicy.policyRevision, gate.revision)
        XCTAssertEqual(newlyRestrictedPolicy.decision(for: item), .blockedByContentPolicy)
        XCTAssertTrue(newlyRestrictedPolicy.filter([item]).isEmpty)
    }

    func test_downloadAccessAlsoChecksThePinnedServerMetadata() {
        let item = makeDownloadItem(id: "re-rated", type: .movie, contentRating: "G", ownerID: owner.id)
        var reRated = item.metadata
        reRated.contentRating = "R"
        let pinned = reRated.localMediaItem

        let policy = DownloadAccessPolicy(
            activeOwnerIDs: [owner.id],
            gate: pgGate(),
            pinnedMedia: { _ in pinned }
        )

        XCTAssertFalse(policy.isAllowedByContentPolicy(item))
        XCTAssertEqual(policy.decision(for: item), .blockedByContentPolicy)
    }

    func test_downloadAccessReturnsOnlyActiveProfileDownloads() {
        let current1 = makeDownloadItem(id: "current-1", type: .movie, contentRating: "G", ownerID: owner.id)
        let current2 = makeDownloadItem(id: "current-2", type: .movie, contentRating: "G", ownerID: owner.id)
        let other = makeDownloadItem(id: "other", type: .movie, contentRating: "G", ownerID: otherOwner.id)
        let policy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: pgGate())

        XCTAssertEqual(policy.filter([current1, other, current2]).map(\.id), ["current-1", "current-2"])
        XCTAssertEqual(policy.decision(for: other), .wrongOwner)
    }

    func test_legacyUnownedDownloadIsNotSharedEvenWhenAllowedByCurrentPolicy() {
        // Pre-fork "grandfathered" downloads were shared with every profile; they now stay unowned (parent-only).
        let item = makeDownloadItem(id: "legacy", type: .movie, contentRating: "G", ownerID: nil)
        let policy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: pgGate())

        XCTAssertTrue(policy.isAllowedByContentPolicy(item))
        XCTAssertEqual(policy.decision(for: item), .missingOwner)
        XCTAssertTrue(policy.filter([item]).isEmpty)
    }

    func test_legacyDownloadStillRespectsCurrentRatingLimit() {
        let item = makeDownloadItem(id: "legacy-restricted", type: .movie, contentRating: "R", ownerID: nil)
        let policy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: pgGate())

        XCTAssertEqual(policy.decision(for: item), .blockedByContentPolicy)
    }

    func test_newOwnerlessDownloadFailsClosed() {
        let item = makeDownloadItem(id: "unprovenanced", type: .movie, contentRating: "G", ownerID: nil)

        XCTAssertEqual(DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: pgGate()).decision(for: item), .missingOwner)
        XCTAssertEqual(DownloadAccessPolicy(activeOwnerIDs: [], gate: pgGate()).decision(for: item), .missingOwner)
    }

    // MARK: - Helpers

    /// The parent's ceiling used by most access tests: PG movies, TV-PG television, no unrated content.
    private func pgGate() -> ContentSafetyGate {
        ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false))
    }

    private func makeLocalPlayerViewModel() -> (PlayerViewModel, URL) {
        let item = makeDownloadItem(id: "dl-1", type: .movie, title: "Offline Movie")
        let url = URL(fileURLWithPath: "/tmp/test-downloads/dl-1/video.mp4")
        let viewModel = PlayerViewModel(
            localMedia: item.metadata.localMediaItem,
            localPlaybackURL: url
        )
        return (viewModel, url)
    }

    private func makeDownloadItem(
        id: String,
        type: MediaKind,
        title: String = "Test",
        status: DownloadStatus = .completed,
        duration: TimeInterval? = 3600,
        grandparentTitle: String? = nil,
        parentTitle: String? = nil,
        parentIndex: Int? = nil,
        index: Int? = nil,
        contentRating: String? = nil,
        ownerID: String? = nil
    ) -> DownloadItem {
        DownloadItem(
            id: id,
            status: status,
            progress: status == .completed ? 1 : 0.5,
            bytesWritten: 100,
            totalBytes: 100,
            taskIdentifier: nil,
            remoteReference: nil,
            trackPreference: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                identity: MediaIdentity(server: server, itemID: id),
                guid: "guid://\(id)",
                type: type,
                title: title,
                summary: nil,
                genres: [],
                year: 2024,
                duration: duration,
                viewCount: nil,
                contentRating: contentRating,
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
                requestedQuality: .original,
                effectiveQuality: .original,
                audioTitle: nil,
                subtitleTitle: nil,
                createdAt: Date()
            ),
            ownerID: ownerID
        )
    }
}
