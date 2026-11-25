import Foundation
@testable import Plinx
import PlinxCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PlaybackLauncherTests — the final check before the player opens
// ─────────────────────────────────────────────────────────────────────────────
//
// `PlaybackLauncher` is the last check every playback start goes through.
// These tests give it services whose own gate lets everything through
// (`ContentSafetyGate.unrestrictedForTests()`), so each block below comes from
// the launcher itself: its gate (a caller's own policy is a
// `ContentSafetyGate(policy:)`), the series ratings that gate knows, the
// whole-queue check, the offline download checks and the cancellation checks.
// Every launcher reads downloads and reachability from a stub offline source,
// never from the app's `OfflineCoordinator` or `DownloadManager`.
//
// Allowed controls on the same fixtures (the `starts` and `plays` tests, and
// the first launch of the explicit-policy and series tests) fail if the
// launcher refuses everything, so no block below passes for that reason alone.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PlaybackLauncherTests: XCTestCase {
    private let server = ServerIdentity(provider: .jellyfin, id: "launcher-server")
    private lazy var owner = MediaOwner(server: server, userID: "kid")
    private lazy var otherOwner = MediaOwner(server: server, userID: "sibling")

    // MARK: - Starting title

    func test_play_startsWhenTheTitleAndEveryQueueMemberAreAllowed() async {
        let fixture = makeFixture()
        fixture.service.titles["ep1"] = episode("ep1", rating: "TV-Y7")
        fixture.service.queueTitles = [episode("ep1", rating: "TV-Y7"), episode("ep2", rating: "TV-Y7")]

        let result = await fixture.launcher.play(
            ratingKey: "ep1",
            type: .episode,
            shouldResumeFromOffset: false,
        )

        XCTAssertEqual(result, .started)
        XCTAssertEqual(fixture.presenter.presentedQueues.map { $0.items.map(\.media.id) }, [["ep1", "ep2"]])
        XCTAssertTrue(fixture.presenter.presentedServices.first === fixture.services)
        XCTAssertEqual(fixture.presenter.resumeFlags, [false])
        XCTAssertTrue(fixture.presenter.localRequests.isEmpty)
    }

    /// The screen showed the title earlier; the fresh lookup finds it above the ceiling now.
    func test_play_blocksATitleTheFreshLookupFindsOverTheCeiling() async {
        let fixture = makeFixture()
        fixture.service.titles["movie"] = movie("movie", rating: "R")
        fixture.service.queueTitles = [movie("movie", rating: "R")]

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
        XCTAssertEqual(fixture.service.calls, ["mediaItem:movie"], "A blocked title never asks for a queue")
    }

    func test_play_blocksATitleTheBoundaryRefuses() async {
        let fixture = makeFixture(servicesGate: kidGate())
        fixture.service.titles["movie"] = movie("movie", rating: "R")

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
    }

    // MARK: - Queue members

    /// The hard-fork plan's autoplay case: the next episode is over the ceiling.
    func test_play_blocksAQueueWhoseNextEpisodeIsOverTheLaunchersGate() async {
        let fixture = makeFixture()
        fixture.service.titles["ep1"] = episode("ep1", rating: "TV-Y7")
        fixture.service.queueTitles = [episode("ep1", rating: "TV-Y7"), episode("ep2", rating: "TV-14")]

        let result = await fixture.launcher.play(ratingKey: "ep1", type: .episode)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
    }

    /// Unrated episodes are what Jellyfin sends almost always: each takes its series' rating, as the gate knows it.
    func test_play_judgesUnratedEpisodesAgainstTheirSeries() async {
        let gate = kidGate()
        await gate.learnSeries(
            of: [series("kids-show", rating: "TV-Y7"), series("teen-show", rating: "TV-14")],
            lookup: { _ in throw URLError(.notConnectedToInternet) },
        )
        let fixture = makeFixture(launcherGate: gate)
        fixture.service.titles["ep1"] = episode("ep1", rating: nil, series: "kids-show")
        fixture.service.queueTitles = [
            episode("ep1", rating: nil, series: "kids-show"),
            episode("ep2", rating: nil, series: "kids-show"),
        ]

        let allowed = await fixture.launcher.play(ratingKey: "ep1", type: .episode)
        XCTAssertEqual(allowed, .started, "An unrated episode of a TV-Y7 series counts as TV-Y7, not as unrated")

        fixture.service.queueTitles = [
            episode("ep1", rating: nil, series: "kids-show"),
            episode("ep3", rating: nil, series: "teen-show"),
        ]
        let teen = await fixture.launcher.play(ratingKey: "ep1", type: .episode)
        XCTAssertEqual(teen, .blocked, "The next episode belongs to a TV-14 series")

        fixture.service.titles["ep4"] = episode("ep4", rating: nil, series: "unknown-show")
        fixture.service.queueTitles = [episode("ep4", rating: nil, series: "unknown-show")]
        let unknown = await fixture.launcher.play(ratingKey: "ep4", type: .episode)
        XCTAssertEqual(unknown, .blocked, "Without its series' rating an unrated episode stays blocked")

        XCTAssertEqual(fixture.presenter.presentedQueues.count, 1, "Only the allowed queue was presented")
    }

    /// A caller with its own policy passes it as the launcher's gate.
    func test_play_followsAnExplicitPolicyGate() async {
        // Stricter than the kid ceiling, which allows PG.
        let fixture = makeFixture(launcherGate: ContentSafetyGate(policy: .ratingOnly(max: .g)))
        fixture.service.titles["g"] = movie("g", rating: "G")
        fixture.service.queueTitles = [movie("g", rating: "G")]

        let allowed = await fixture.launcher.play(ratingKey: "g", type: .movie)
        XCTAssertEqual(allowed, .started)

        fixture.service.titles["pg"] = movie("pg", rating: "PG")
        fixture.service.queueTitles = [movie("pg", rating: "PG")]
        let blocked = await fixture.launcher.play(ratingKey: "pg", type: .movie)

        XCTAssertEqual(blocked, .blocked)
        XCTAssertEqual(fixture.presenter.presentedQueues.count, 1, "Only the allowed queue was presented")
    }

    func test_play_emptyQueueNeverPresents() async {
        let fixture = makeFixture()
        fixture.service.titles["movie"] = movie("movie", rating: "G")
        fixture.service.queueTitles = []

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
    }

    func test_play_failedRequestNeverPresents() async {
        let fixture = makeFixture()

        // `mediaItem(id:)` is not stubbed for this title, so the request throws.
        let result = await fixture.launcher.play(ratingKey: "missing", type: .movie)

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
    }

    // MARK: - Cancellation

    func test_play_neverPresentsWhenTheCallerCancelled() async {
        let fixture = makeFixture()
        fixture.service.titles["movie"] = movie("movie", rating: "G")
        fixture.service.queueTitles = [movie("movie", rating: "G")]

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie, shouldContinue: { false })

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
        XCTAssertEqual(fixture.service.calls, ["mediaItem:movie", "queue:movie"])
    }

    func test_play_neverPresentsWhenItsTaskIsCancelled() async {
        let fixture = makeFixture()
        fixture.service.titles["movie"] = movie("movie", rating: "G")
        fixture.service.queueTitles = [movie("movie", rating: "G")]
        fixture.service.cancelsTaskDuringQueue = true
        let launcher = fixture.launcher

        let result = await Task { await launcher.play(ratingKey: "movie", type: .movie) }.value

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
    }

    // MARK: - Playlists

    func test_playPlaylist_startsWhenEveryEntryIsAllowed() async {
        let fixture = makeFixture()
        fixture.service.titles["first"] = movie("first", rating: "PG")
        fixture.service.queueTitles = [movie("first", rating: "PG"), movie("second", rating: "G")]

        let start = entry(movie("first", rating: "PG"))
        let result = await fixture.launcher.playPlaylist(id: "playlist", startingWith: start)

        XCTAssertEqual(result, .started)
        XCTAssertEqual(fixture.presenter.presentedQueues.map { $0.items.map(\.media.id) }, [["first", "second"]])
    }

    func test_playPlaylist_blocksABlockedEntryBeforeAskingTheServer() async {
        let fixture = makeFixture()
        fixture.service.titles["first"] = movie("first", rating: "R")
        fixture.service.queueTitles = [movie("first", rating: "R")]

        let start = entry(movie("first", rating: "R"))
        let result = await fixture.launcher.playPlaylist(id: "playlist", startingWith: start)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
        XCTAssertEqual(fixture.service.calls, [])
    }

    func test_playPlaylist_blocksAnEntryReRatedSinceTheListLoaded() async {
        let fixture = makeFixture()
        fixture.service.titles["first"] = movie("first", rating: "R")
        fixture.service.queueTitles = [movie("first", rating: "R")]

        let start = entry(movie("first", rating: "PG"))
        let result = await fixture.launcher.playPlaylist(id: "playlist", startingWith: start)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
        XCTAssertEqual(fixture.service.calls, ["mediaItem:first"])
    }

    func test_playPlaylist_blocksAPlaylistWithALaterBlockedEntry() async {
        let fixture = makeFixture()
        fixture.service.titles["first"] = movie("first", rating: "PG")
        fixture.service.queueTitles = [movie("first", rating: "PG"), movie("second", rating: "R")]

        let start = entry(movie("first", rating: "PG"))
        let result = await fixture.launcher.playPlaylist(id: "playlist", startingWith: start)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
    }

    func test_playPlaylist_neverStartsFromANestedPlaylist() async {
        let fixture = makeFixture()
        let nested = PlaylistMediaItem(
            id: "nested",
            key: "nested",
            guid: "test://nested",
            type: .playlist,
            title: "Nested",
            summary: nil,
            compositePath: nil,
            duration: nil,
            leafCount: nil,
            playlistType: "video",
            server: server,
        )

        let result = await fixture.launcher.playPlaylist(
            id: "playlist",
            startingWith: PlaylistEntry(id: "nested", entryID: "nested", media: .playlist(nested)),
        )

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
        XCTAssertEqual(fixture.service.calls, [])
    }

    func test_playPlaylist_neverPresentsWhenTheCallerCancelled() async {
        let fixture = makeFixture()
        fixture.service.titles["first"] = movie("first", rating: "PG")
        fixture.service.queueTitles = [movie("first", rating: "PG")]

        let result = await fixture.launcher.playPlaylist(
            id: "playlist",
            startingWith: entry(movie("first", rating: "PG")),
            shouldContinue: { false },
        )

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
    }

    // MARK: - Offline

    func test_offline_playsTheActiveProfilesAllowedDownload() async {
        let fixture = makeFixture()
        fixture.offline.unreachable = [server]
        fixture.offline.activeOwnerIDs = [owner.id]
        let downloaded = download("movie", rating: "G", ownerID: owner.id)
        fixture.offline.playback = downloaded

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

        XCTAssertEqual(result, .started)
        XCTAssertEqual(fixture.presenter.localRequests.map(\.id), [downloaded.request.id])
        XCTAssertTrue(fixture.presenter.presentedQueues.isEmpty)
        XCTAssertEqual(fixture.offline.lookups, [MediaIdentity(server: server, itemID: "movie")])
        XCTAssertEqual(fixture.service.calls, [], "Offline playback never asks the unreachable server")
    }

    func test_offline_blocksADownloadOfAnotherProfileOrWithoutOwner() async {
        for ownerID in [otherOwner.id, nil] {
            let fixture = makeFixture()
            fixture.offline.unreachable = [server]
            fixture.offline.activeOwnerIDs = [owner.id]
            fixture.offline.playback = download("movie", rating: "G", ownerID: ownerID)

            let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

            XCTAssertEqual(result, .blocked, "owner \(ownerID ?? "none")")
            assertNothingPresented(fixture.presenter)
            XCTAssertFalse(fixture.launcher.playDownloaded(ratingKey: "movie", type: .movie))
        }
    }

    func test_offline_blocksADownloadWhosePinnedMetadataIsOverTheCeiling() async {
        let fixture = makeFixture()
        fixture.offline.unreachable = [server]
        fixture.offline.activeOwnerIDs = [owner.id]
        let downloaded = download("movie", rating: "G", ownerID: owner.id)
        fixture.offline.playback = downloaded
        // The server re-rated the title after it was downloaded.
        fixture.offline.pinned[downloaded.download.id] = movie("movie", rating: "R")

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
        XCTAssertFalse(fixture.launcher.playDownloaded(ratingKey: "movie", type: .movie))
    }

    func test_offline_blocksADownloadOverAnExplicitPolicyGate() async {
        let fixture = makeFixture(launcherGate: ContentSafetyGate(policy: .ratingOnly(max: .g)))
        fixture.offline.unreachable = [server]
        fixture.offline.activeOwnerIDs = [owner.id]
        fixture.offline.playback = download("movie", rating: "PG", ownerID: owner.id)

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
    }

    func test_offline_playlistEntryPlaysOnlyAnAllowedDownload() async {
        let fixture = makeFixture()
        fixture.offline.unreachable = [server]
        fixture.offline.activeOwnerIDs = [owner.id]
        let downloaded = download("first", rating: "G", ownerID: owner.id)
        fixture.offline.playback = downloaded
        fixture.offline.pinned[downloaded.download.id] = movie("first", rating: "R")

        let start = entry(movie("first", rating: "G"))
        let result = await fixture.launcher.playPlaylist(id: "playlist", startingWith: start)

        XCTAssertEqual(result, .blocked)
        assertNothingPresented(fixture.presenter)
        XCTAssertEqual(fixture.service.calls, [])
    }

    func test_offline_withoutADownloadNeverPresents() async {
        let fixture = makeFixture()
        fixture.offline.unreachable = [server]
        fixture.offline.activeOwnerIDs = [owner.id]

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
        XCTAssertEqual(fixture.service.calls, [])
    }

    func test_offline_refusesADownloadThatIsNotTheRequestedServersCompletedCopy() async {
        let elsewhere = ServerIdentity(provider: .jellyfin, id: "other-server")
        var otherServer = download("movie", rating: "G", ownerID: owner.id)
        otherServer.download.metadata.identity = MediaIdentity(server: elsewhere, itemID: "movie")
        var unfinished = download("movie", rating: "G", ownerID: owner.id)
        unfinished.download.status = .downloading

        for (name, downloaded) in [("other server", otherServer), ("unfinished", unfinished)] {
            let fixture = makeFixture()
            fixture.offline.unreachable = [server]
            fixture.offline.activeOwnerIDs = [owner.id]
            fixture.offline.playback = downloaded

            let result = await fixture.launcher.play(ratingKey: "movie", type: .movie)

            XCTAssertEqual(result, .failed, name)
            assertNothingPresented(fixture.presenter)
        }
    }

    func test_offline_neverPresentsWhenTheCallerCancelled() async {
        let fixture = makeFixture()
        fixture.offline.unreachable = [server]
        fixture.offline.activeOwnerIDs = [owner.id]
        fixture.offline.playback = download("movie", rating: "G", ownerID: owner.id)

        let result = await fixture.launcher.play(ratingKey: "movie", type: .movie, shouldContinue: { false })

        XCTAssertEqual(result, .failed)
        assertNothingPresented(fixture.presenter)
    }

    // MARK: - Switching services

    func test_usingServicesKeepsTheGateAndOfflineSource() async {
        let fixture = makeFixture(launcherGate: ContentSafetyGate(policy: .ratingOnly(max: .g)))
        let elsewhere = ServerIdentity(provider: .plex, id: "other-server")
        let otherService = LauncherFakeService()
        let otherServices = MediaServices.fake(otherService, server: elsewhere, capabilities: .plex)
        otherService.titles["movie"] = movie("movie", rating: "PG", server: elsewhere)
        otherService.queueTitles = [movie("movie", rating: "PG", server: elsewhere)]

        let switched = fixture.launcher.using(services: otherServices)

        XCTAssertTrue(switched.gate === fixture.launcher.gate)
        let result = await switched.play(ratingKey: "movie", type: .movie)
        XCTAssertEqual(result, .blocked, "The launcher's gate still applies on the new server")

        fixture.offline.unreachable = [elsewhere]
        _ = await switched.play(ratingKey: "movie", type: .movie)
        XCTAssertEqual(
            fixture.offline.lookups,
            [MediaIdentity(server: elsewhere, itemID: "movie")],
            "The new launcher still reads the same offline source",
        )
    }

    // MARK: - Helpers

    private struct Fixture {
        let service: LauncherFakeService
        let services: MediaServices
        let presenter: RecordingPresenter
        let offline: StubOfflineSource
        let launcher: PlaybackLauncher
    }

    /// The parent's ceiling for these tests: PG movies, TV-Y7 television, no unrated content.
    private func kidGate() -> ContentSafetyGate {
        ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg, maxTV: .tvY7))
    }

    /// - Parameters:
    ///   - servicesGate: the boundary's gate; permissive by default so the launcher's own checks decide.
    ///   - launcherGate: the launcher's gate; the kid ceiling by default.
    private func makeFixture(
        servicesGate: ContentSafetyGate? = nil,
        launcherGate: ContentSafetyGate? = nil,
    ) -> Fixture {
        let service = LauncherFakeService()
        let services = MediaServices.fake(
            service,
            server: server,
            contentGate: servicesGate ?? .unrestrictedForTests(),
        )
        let presenter = RecordingPresenter()
        let offline = StubOfflineSource()
        let launcher = PlaybackLauncher(
            services: services,
            coordinator: presenter,
            gate: launcherGate ?? kidGate(),
        ).using(offline: offline)
        return Fixture(service: service, services: services, presenter: presenter, offline: offline, launcher: launcher)
    }

    private func assertNothingPresented(
        _ presenter: RecordingPresenter,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertTrue(presenter.presentedQueues.isEmpty, "The player was presented", file: file, line: line)
        XCTAssertTrue(presenter.localRequests.isEmpty, "The local player was presented", file: file, line: line)
    }

    private func movie(_ id: String, rating: String?, server: ServerIdentity? = nil) -> MediaItem {
        title(id, rating: rating, type: .movie, server: server ?? self.server)
    }

    /// An episode with its own rating and, unless `series` names one, no series, so the gate judges it on that
    /// rating alone.
    private func episode(_ id: String, rating: String?, series: String? = nil) -> MediaItem {
        title(id, rating: rating, type: .episode, server: server, series: series)
    }

    private func series(_ id: String, rating: String?) -> MediaItem {
        title(id, rating: rating, type: .series, server: server)
    }

    /// - Parameter series: the series of an episode (its grandparent, as on Plex and Jellyfin).
    private func title(
        _ id: String,
        rating: String?,
        type: MediaKind,
        server: ServerIdentity,
        series: String? = nil,
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: "test://\(id)",
            summary: nil,
            title: id,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: series,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: rating,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        )
    }

    private func entry(_ media: MediaItem) -> PlaylistEntry {
        PlaylistEntry(id: media.id, entryID: media.id, media: .playable(media))
    }

    /// A completed download of this server, with the request that plays it from its stored metadata.
    private func download(
        _ itemID: String,
        rating: String?,
        ownerID: String?,
    ) -> (request: LocalPlaybackRequest, download: DownloadItem) {
        var item = DownloadItem.make(id: "download-\(itemID)", itemID: itemID, server: server, ownerID: ownerID)
        item.metadata.contentRating = rating
        let request = LocalPlaybackRequest(
            media: item.localMediaItem,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id).mp4"),
            externalSubtitles: [],
            owner: nil,
            resumes: true,
        )
        return (request, item)
    }
}

// MARK: - Test doubles

/// Serves the titles and queue a test sets, and records the requests that reach it.
private final class LauncherFakeService: FakeMediaService {
    var titles: [String: MediaItem] = [:]
    var queueTitles: [MediaItem] = []
    /// Cancels the launching task while its queue is requested, as when the screen that started it goes away.
    var cancelsTaskDuringQueue = false
    private(set) var calls: [String] = []

    override func mediaItem(id: String) async throws -> MediaItem {
        calls.append("mediaItem:\(id)")
        guard let title = titles[id] else { throw FakeMediaService.NotStubbed(function: #function) }
        return title
    }

    override func queue(startingWith itemID: String, kind _: MediaKind, shuffle _: Bool) async throws -> PlaybackQueue {
        calls.append("queue:\(itemID)")
        return makeQueue(startingAt: itemID)
    }

    override func queue(playlistID: String, startingWith entry: PlaylistEntry) async throws -> PlaybackQueue {
        calls.append("playlistQueue:\(playlistID)")
        return makeQueue(startingAt: entry.media.playableItem?.id)
    }

    private func makeQueue(startingAt id: String?) -> PlaybackQueue {
        if cancelsTaskDuringQueue {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return PlaybackQueue(media: queueTitles, startingAt: id, shuffle: false)
    }
}

@MainActor
private final class RecordingPresenter: PlaybackPresenting {
    private(set) var presentedQueues: [PlaybackQueue] = []
    private(set) var presentedServices: [MediaServices] = []
    private(set) var resumeFlags: [Bool] = []
    private(set) var localRequests: [LocalPlaybackRequest] = []

    func showPlayer(
        for queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool,
        notice _: String?,
    ) {
        presentedQueues.append(queue)
        presentedServices.append(services)
        resumeFlags.append(shouldResumeFromOffset)
    }

    func showLocalPlayer(_ request: LocalPlaybackRequest) {
        localRequests.append(request)
    }
}

/// Downloads and reachability as a test sets them. It returns whatever download it holds, even one the active
/// profile must not play, so the launcher's own checks are what refuse it.
@MainActor
private final class StubOfflineSource: OfflinePlaybackSource {
    var unreachable: Set<ServerIdentity> = []
    var playback: (request: LocalPlaybackRequest, download: DownloadItem)?
    var activeOwnerIDs: Set<String> = []
    /// Pinned server metadata by download ID.
    var pinned: [String: MediaItem] = [:]
    private(set) var lookups: [MediaIdentity] = []

    func isUnreachable(_ server: ServerIdentity) -> Bool {
        unreachable.contains(server)
    }

    func downloadedPlayback(
        for identity: MediaIdentity,
        kind _: MediaKind,
        resumes _: Bool,
    ) -> (request: LocalPlaybackRequest, download: DownloadItem)? {
        lookups.append(identity)
        return playback
    }

    func pinnedMedia(for download: DownloadItem) -> MediaItem? {
        pinned[download.id]
    }
}
