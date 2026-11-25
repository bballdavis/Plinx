import Foundation
import AVFoundation
import PlinxCore
import XCTest
@testable import Plinx

/// The sample catalog answers by path and query only; any host reaches it.
private let demoBaseURL = "http://demo.plinx.invalid"

@MainActor
final class DemoFixtureTests: XCTestCase {
    func testPlexCloudStandInAnswersOnlyPlexTVRequestsCarryingARegisteredToken() throws {
        let token = "plinx-stand-in-test-\(UUID().uuidString)"
        let session = try XCTUnwrap(PlexDirectSession(
            userUUID: "plinx-stand-in-test",
            displayName: "Stand-in Test",
            token: token,
            serverName: "Stand-in Test Server",
            serverIdentifier: "plinx-stand-in-test-server",
            serverURL: URL(string: "http://127.0.0.1:32400")!
        ))
        PlexCloudStandIn.register(session)
        defer { PlexCloudStandIn.unregister(token: token) }

        func request(_ string: String, token: String?, method: String = "GET") -> URLRequest {
            var request = URLRequest(url: URL(string: string)!)
            request.httpMethod = method
            if let token {
                request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
            }
            return request
        }

        // Answered on the device: plex.tv and its subdomains, with the registered token in a header or the query.
        XCTAssertTrue(PlexCloudStandIn.canInit(with: request("https://plex.tv/api/v2/resources", token: token)))
        XCTAssertTrue(PlexCloudStandIn.canInit(with: request("https://clients.plex.tv/api/v2/user", token: token)))
        XCTAssertTrue(PlexCloudStandIn.canInit(with: request("https://plex.tv/api/v2/user?X-Plex-Token=\(token)", token: nil)))
        // Never touched: other tokens, sign-in without a token, the server itself and look-alike hosts.
        XCTAssertFalse(PlexCloudStandIn.canInit(with: request("https://plex.tv/api/v2/user", token: "family-token")))
        XCTAssertFalse(PlexCloudStandIn.canInit(with: request("https://plex.tv/api/v2/pins", token: nil, method: "POST")))
        XCTAssertFalse(PlexCloudStandIn.canInit(with: request("http://127.0.0.1:32400/library/sections", token: token)))
        XCTAssertFalse(PlexCloudStandIn.canInit(with: request("https://notplex.tv/api/v2/user", token: token)))
        XCTAssertFalse(PlexCloudStandIn.canInit(with: request("https://plex.tv.example.com/api/v2/user", token: token)))

        // The resources are the session's one loopback server, which the account does not administer.
        let resources = try XCTUnwrap(PlexCloudStandIn.response(for: request("https://plex.tv/api/v2/resources", token: token)))
        XCTAssertEqual(resources.statusCode, 200)
        let decoded = try JSONDecoder().decode([PlexCloudResource].self, from: resources.body)
        XCTAssertEqual(decoded, [session.resource])
        XCTAssertEqual(decoded.first?.connections?.first?.address, "127.0.0.1")
        XCTAssertEqual(decoded.first?.owned, false)

        // Anything without a stand-in answer is refused on the device instead of being sent with the token.
        let watchlist = request("https://discover.provider.plex.tv/library/sections/watchlist/all", token: token)
        XCTAssertTrue(PlexCloudStandIn.canInit(with: watchlist))
        XCTAssertEqual(PlexCloudStandIn.response(for: watchlist)?.statusCode, 404)

        // Once unregistered, the token is no longer answered.
        PlexCloudStandIn.unregister(token: token)
        XCTAssertFalse(PlexCloudStandIn.canInit(with: request("https://plex.tv/api/v2/resources", token: token)))
        XCTAssertNil(PlexCloudStandIn.response(for: request("https://plex.tv/api/v2/resources", token: token)))
    }

    func testSampleLibraryNeverJoinsAnExistingFamilySession() async throws {
        defer { DemoFixtureBootstrap.stop() }
        let family = MediaAccount.jellyfin(JellyfinAccount(connection: JellyfinConnection(
            baseURL: URL(string: "https://family.invalid")!,
            serverID: "family-server",
            serverName: "Family",
            serverVersion: "10.11.0",
            userID: "family-user",
            username: "Family"
        )))
        let session = try makeIsolatedSession(accounts: [(family, "family-token")])
        try await waitForHydration(of: session)
        let statusBefore = session.status
        XCTAssertNotEqual(statusBefore, .needsAccount)

        await DemoFixtureBootstrap.start(sessionManager: session)

        XCTAssertFalse(DemoFixtureBootstrap.isActive)
        XCTAssertEqual(session.accounts.map(\.id), [family.id])
        XCTAssertNil(session.accountStore.account(id: DemoFixtureBootstrap.accountID))
        XCTAssertEqual(session.status, statusBefore)
    }

    func testSectionsFixtureIncludesDedicatedRatingLibraries() throws {
        let request = URLRequest(url: URL(string: "\(demoBaseURL)/library/sections/all")!)
        let response = DemoFixtureCatalog.response(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let container = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let sections = try XCTUnwrap(container["Directory"] as? [[String: Any]])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(sections.count, 5)
        XCTAssertEqual(sections.compactMap { $0["title"] as? String }, ["Family Movies", "Family TV", "Learning Videos", "Rating Test Movies", "Rating Test TV"])
    }

    func testDemoHomeContainsContinueWatchingAndEnoughRows() throws {
        let request = URLRequest(url: URL(string: "\(demoBaseURL)/hubs/continueWatching")!)
        let response = DemoFixtureCatalog.response(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let mediaContainer = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let hubs = try XCTUnwrap(mediaContainer["Hub"] as? [[String: Any]])
        let items = try XCTUnwrap(hubs.first?["Metadata"] as? [[String: Any]])

        XCTAssertEqual(hubs.first?["title"] as? String, "Continue Watching")
        XCTAssertGreaterThanOrEqual(items.count, 6)
        XCTAssertTrue(items.allSatisfy { ($0["contentRating"] as? String) != nil })
    }

    func testDemoSearchReturnsFictionalMatchingContent() throws {
        var components = URLComponents(string: "\(demoBaseURL)/library/search")!
        components.queryItems = [URLQueryItem(name: "query", value: "moon")]
        let request = URLRequest(url: components.url!)
        let response = DemoFixtureCatalog.response(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let mediaContainer = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let results = try XCTUnwrap(mediaContainer["SearchResult"] as? [[String: Any]])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual((results.first?["Metadata"] as? [String: Any])?["title"] as? String, "Moonbound")
    }

    func testDemoRelatedContentReturnsAHub() throws {
        let request = URLRequest(url: URL(string: "\(demoBaseURL)/library/metadata/moonbound/related")!)
        let response = DemoFixtureCatalog.response(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let mediaContainer = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let hubs = try XCTUnwrap(mediaContainer["Hub"] as? [[String: Any]])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(hubs.first?["title"] as? String, "More Like This")
        XCTAssertGreaterThanOrEqual((hubs.first?["Metadata"] as? [[String: Any]])?.count ?? 0, 1)
        let decoded = try JSONDecoder().decode(PlexHubMediaContainer.self, from: response.data)
        XCTAssertEqual(decoded.mediaContainer.hub?.first?.title, "More Like This")
    }

    func testDemoPlayQueueReturnsTheRequestedItem() throws {
        var components = URLComponents(string: "\(demoBaseURL)/playQueues")!
        components.queryItems = [URLQueryItem(name: "uri", value: "/library/metadata/moonbound")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let response = DemoFixtureCatalog.response(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let mediaContainer = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let items = try XCTUnwrap(mediaContainer["Metadata"] as? [[String: Any]])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(items.first?["title"] as? String, "Moonbound")
        XCTAssertEqual(mediaContainer["playQueueSelectedItemID"] as? Int, 1)
        let decoded = try JSONDecoder().decode(PlexPlayQueueResponse.self, from: response.data)
        XCTAssertEqual(decoded.mediaContainer.metadata?.first?.title, "Moonbound")
    }
    func testByteRangesAndHeadPreserveMediaLengths() throws {
        XCTAssertEqual(DemoHTTPResponse.byteRange("bytes=10-19", count: 100), 10...19)
        XCTAssertEqual(DemoHTTPResponse.byteRange("bytes=95-", count: 100), 95...99)
        XCTAssertEqual(DemoHTTPResponse.byteRange("bytes=-10", count: 100), 90...99)
        for invalid in ["bytes=100-", "bytes=-0", "bytes=9-1", "bytes=0-1,3-4", "bytes=no-", "items=1-2"] {
            XCTAssertNil(DemoHTTPResponse.byteRange(invalid, count: 100), invalid)
        }
        let data = Data(0..<100)
        let response = DemoFixtureResponse(statusCode: 200, mimeType: "video/mp4", data: data)
        var request = URLRequest(url: URL(string: "http://127.0.0.1/video/movie.mp4")!)
        request.setValue("bytes=10-19", forHTTPHeaderField: "Range")
        let payload = DemoHTTPResponse.encode(response, request: request)
        XCTAssertTrue(String(decoding: payload, as: UTF8.self).contains("Content-Range: bytes 10-19/100"))
        XCTAssertTrue(payload.suffix(10).elementsEqual(data[10..<20]))
        request.httpMethod = "HEAD"
        let head = String(decoding: DemoHTTPResponse.encode(response, request: request), as: UTF8.self)
        XCTAssertTrue(head.hasSuffix("\r\n\r\n"))
        XCTAssertTrue(head.contains("Content-Length: 10"))
    }

    func testBundledSamplesContainRealAudioAndVideo() async throws {
        XCTAssertTrue(DemoSampleMedia.isAvailable)
        for isEpisode in [false, true] {
            let url = try XCTUnwrap(DemoSampleMedia.url(isEpisode: isEpisode))
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 90, accuracy: 0.1)
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(video.count, 1)
            XCTAssertEqual(audio.count, 2)
        }
    }

    func testEpisodeQueueKeepsTheRequestedEpisode() throws {
        let id = "space-camp-season-1-e-2"
        var request = URLRequest(url: URL(string: "\(demoBaseURL)/playQueues?uri=/library/metadata/\(id)")!)
        request.httpMethod = "POST"
        let response = try JSONDecoder().decode(PlexPlayQueueResponse.self, from: DemoFixtureCatalog.response(for: request).data)
        XCTAssertEqual(response.mediaContainer.metadata?.first?.ratingKey, id)
        let videoRequest = URLRequest(url: URL(string: "\(demoBaseURL)/video/\(id).mp4")!)
        let video = DemoFixtureCatalog.response(for: videoRequest)
        XCTAssertEqual(video.mimeType, "video/mp4")
        XCTAssertEqual(video.data.count, DemoSampleMedia.byteCount(isEpisode: true))
        let unknown = URLRequest(url: URL(string: "\(demoBaseURL)/video/not-an-item.mp4")!)
        XCTAssertEqual(DemoFixtureCatalog.response(for: unknown).statusCode, 404)
    }

    func testMixedCollectionActuallyExercisesSafetyFiltering() throws {
        let request = URLRequest(url: URL(string: "\(demoBaseURL)/library/collections/demo-mix/children")!)
        let response = try JSONDecoder().decode(PlexItemMediaContainer.self, from: DemoFixtureCatalog.response(for: request).data)
        let items = try XCTUnwrap(response.mediaContainer.metadata)
        XCTAssertEqual(items.count, 4)
        let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        let permitted = items.filter { PlinxContentRules.isAllowed(MediaItem(plexItem: $0), policy: policy) }
        XCTAssertEqual(Set(permitted.map(\.ratingKey)), ["moonbound", "hidden-gardens"])
    }

    func testRatingLibrariesFilterEveryCeilingIndependentlyThroughProductionLoader() async throws {
        defer { DemoFixtureBootstrap.stop() }
        // Every request goes through `SafeMediaServices`, which follows the shared gate; restore the app's policy.
        let originalPolicy = ContentSafetyGate.shared.policy
        defer { ContentSafetyGate.shared.policy = originalPolicy }
        let (_, services) = try await startSampleLibrary()
        let libraries = try await services.library.libraries()
        let movies = try XCTUnwrap(libraries.first(where: { $0.sectionId == 4 }))
        let television = try XCTUnwrap(libraries.first(where: { $0.sectionId == 5 }))
        let loader = LibraryCatalogLoader(services: services)
        let movieCases: [(PlinxRating, [String])] = [
            (.g, ["g"]), (.pg, ["g", "pg"]), (.pg13, ["g", "pg", "pg13"]), (.r, ["g", "pg", "pg13", "r"]),
        ]
        let tvCases: [(PlinxRating, [String])] = [
            (.tvY, ["tvy"]), (.tvY7, ["tvy", "tvy7"]), (.tvG, ["tvy", "tvy7", "tvg"]),
            (.tvPg, ["tvy", "tvy7", "tvg", "tvpg"]),
            (.tv14, ["tvy", "tvy7", "tvg", "tvpg", "tv14"]),
            (.tvMa, ["tvy", "tvy7", "tvg", "tvpg", "tv14", "tvma"]),
        ]
        // Every movie/TV ceiling pair, in both unrated modes. Requests return
        // the full fixture; production authorization does the filtering.
        for (movieCeiling, movieIDs) in movieCases {
            for (tvCeiling, tvIDs) in tvCases {
                for allowUnrated in [false, true] {
                    ContentSafetyGate.shared.policy = SafetyPolicy.ratingOnly(maxMovie: movieCeiling, maxTV: tvCeiling, allowUnrated: allowUnrated)
                    let movieResult = try await loader.recentItems(for: movies, limit: 20)
                    let tvResult = try await loader.recentItems(for: television, limit: 20)
                    let expectedMovies = (movieIDs + (allowUnrated ? ["unrated"] : [])).map { "rating-movie-\($0)" }
                    let expectedTV = (tvIDs + (allowUnrated ? ["unrated"] : [])).map { "rating-tv-\($0)" }
                    XCTAssertEqual(Set(movieResult.items.map { $0.id }), Set(expectedMovies), "Movie \(movieCeiling), TV \(tvCeiling), unrated \(allowUnrated)")
                    XCTAssertEqual(Set(tvResult.items.map { $0.id }), Set(expectedTV), "Movie \(movieCeiling), TV \(tvCeiling), unrated \(allowUnrated)")
                }
            }
        }
        // Lower again after the permissive cases; prior access must not stick.
        ContentSafetyGate.shared.policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        let resetMovies = try await loader.recentItems(for: movies, limit: 20)
        XCTAssertEqual(Set(resetMovies.items.map { $0.id }), ["rating-movie-g", "rating-movie-pg"])
    }

    func testTVRatingExamplesPropagateToSeasonsEpisodesAndPlaybackAuthorization() throws {
        for (key, rating) in [("tvy", "TV-Y"), ("tvy7", "TV-Y7"), ("tvg", "TV-G"), ("tvpg", "TV-PG"), ("tv14", "TV-14"), ("tvma", "TV-MA"), ("unrated", "")] {
            let showID = "rating-tv-\(key)"
            for id in [showID, "\(showID)-season-1", "\(showID)-season-1-e-1"] {
                let request = URLRequest(url: URL(string: "\(demoBaseURL)/library/metadata/\(id)")!)
                let result = DemoFixtureCatalog.response(for: request)
                let response = try JSONDecoder().decode(PlexItemMediaContainer.self, from: result.data)
                let item = try XCTUnwrap(response.mediaContainer.metadata?.first)
                XCTAssertEqual(item.contentRating ?? "", rating)
                XCTAssertEqual(item.librarySectionID, 5)
                let policy = SafetyPolicy.ratingOnly(maxMovie: .r, maxTV: .tvPg, allowUnrated: false)
                XCTAssertEqual(PlinxContentRules.isAllowed(item, policy: policy), !["tv14", "tvma", "unrated"].contains(key))
            }
            let episodesRequest = URLRequest(url: URL(string: "\(demoBaseURL)/library/metadata/\(showID)/grandchildren")!)
            let episodes = try JSONDecoder().decode(PlexItemMediaContainer.self, from: DemoFixtureCatalog.response(for: episodesRequest).data)
            XCTAssertEqual(episodes.mediaContainer.metadata?.count, 4)
        }
        let raw = URLRequest(url: URL(string: "\(demoBaseURL)/library/metadata/rating-movie-unrated")!)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: DemoFixtureCatalog.response(for: raw).data) as? [String: Any])
        let container = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let items = try XCTUnwrap(container["Metadata"] as? [[String: Any]])
        XCTAssertNil(items.first?["contentRating"], "Unrated samples must exercise missing rating metadata")
    }

    func testProductionDownloadCompletesAndRemainsPlayableWithoutServer() async throws {
        defer { DemoFixtureBootstrap.stop() }
        // Downloads are prepared through `SafeMediaServices`, which follows the shared gate; restore the app's policy.
        let originalPolicy = ContentSafetyGate.shared.policy
        defer { ContentSafetyGate.shared.policy = originalPolicy }
        let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        ContentSafetyGate.shared.policy = policy
        let (session, services) = try await startSampleLibrary()
        let manager = try XCTUnwrap(DownloadManager.shared)
        let owner = services.owner
        let gate = ContentSafetyGate(policy: policy)
        let personalOwner = MediaOwner(server: ServerIdentity(provider: .plex, id: "personal-server"), userID: "parent")
        var downloaded: [(DownloadItem, URL)] = []
        for itemID in ["hidden-gardens", "space-camp-season-1-e-2"] {
            // The sample server has no transcoder, so downloads keep the original file.
            let ids = await manager.enqueueItem(itemID: itemID, quality: .original, services: services)
            let id = try XCTUnwrap(ids.first, manager.lastErrorMessage ?? "Download was not created")
            for _ in 0..<200 {
                if manager.items.first(where: { $0.id == id })?.status == .completed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let item = try XCTUnwrap(manager.items.first(where: { $0.id == id }))
            XCTAssertEqual(item.status, .completed, item.errorMessage ?? "Download did not finish")
            let file = try XCTUnwrap(manager.localVideoURL(for: item))
            XCTAssertEqual(try Data(contentsOf: file), DemoSampleMedia.data(isEpisode: itemID != "hidden-gardens"))
            // Owned by the sample profile's server user, and only that owner may use it.
            XCTAssertEqual(item.ownerID, owner.id)
            XCTAssertEqual(DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: gate).decision(for: item), .allowed)
            XCTAssertEqual(DownloadAccessPolicy(activeOwnerIDs: [personalOwner.id], gate: gate).decision(for: item), .wrongOwner)
            downloaded.append((item, file))
        }
        // Ending the sample library removes its account and services; it never leaves a session behind.
        DemoFixtureBootstrap.stop()
        XCTAssertFalse(DemoFixtureBootstrap.isActive)
        XCTAssertNil(session.registry.services(for: DemoFixtureBootstrap.server))
        XCTAssertNil(session.activeProfile)
        XCTAssertTrue(session.accounts.isEmpty)
        XCTAssertEqual(session.status, .needsAccount)
        for (item, file) in downloaded {
            let duration = try await AVURLAsset(url: file).load(.duration)
            XCTAssertEqual(duration.seconds, 90, accuracy: 0.1)
            await manager.delete(item)
        }
    }

    func testYoutarrSampleSupportsCatalogAndRequestLifecycleOverHTTP() async throws {
        let baseURL = try await DemoMediaServer.shared.start()
        defer { DemoMediaServer.shared.stop() }
        DemoYoutarrCatalog.reset()
        let client = YoutarrClient(configuration: try YoutarrConfiguration(baseURL: baseURL, apiKey: "sample"))
        let capabilities = try await client.capabilities()
        XCTAssertTrue(capabilities.features.catalog)
        let channels = try await client.channels()
        XCTAssertFalse(channels.data.isEmpty)
        let videos = try await client.catalogVideos()
        let video = try XCTUnwrap(videos.data.first)
        let detail = try await client.videoDetail(youtubeID: video.youtubeId)
        XCTAssertEqual(detail.youtubeId, video.youtubeId)
        let channelID = try XCTUnwrap(video.channelDatabaseId)
        let created = try await client.requestVideo(youtubeID: video.youtubeId, channelID: channelID)
        XCTAssertEqual(created.outcome, .created)
        let duplicate = try await client.requestVideo(youtubeID: video.youtubeId, channelID: channelID)
        XCTAssertEqual(duplicate.outcome, .duplicate)
        let requests = try await client.requests()
        XCTAssertEqual(requests.data.count, 1)
        XCTAssertEqual(requests.data.first?.videoYoutubeID, video.youtubeId)
        XCTAssertEqual(requests.data.first?.status, .pending)
    }

    func testDemoPreferencesAndPINAreIsolatedFromFamilySettings() {
        let personalMovieRating = UserDefaults.standard.object(forKey: "plinx.maxMovieRating") as? String
        DemoPreferences.reset()
        XCTAssertEqual(DemoPreferences.defaults.string(forKey: "plinx.maxMovieRating"), "PG")
        XCTAssertEqual(DemoPreferences.parentalAccess.unlock(withPIN: "2468"), .allowed)
        DemoPreferences.defaults.set("R", forKey: "plinx.maxMovieRating")
        XCTAssertEqual(UserDefaults.standard.object(forKey: "plinx.maxMovieRating") as? String, personalMovieRating)
        DemoPreferences.reset()
        XCTAssertEqual(DemoPreferences.defaults.string(forKey: "plinx.maxMovieRating"), "PG")
    }

    func testProductionEnginePlaysAndSeeksBundledHTTPMedia() async throws {
        let baseURL = try await DemoMediaServer.shared.start()
        defer { DemoMediaServer.shared.stop() }
        let controller = PlayerController()
        defer { controller.stop() }
        controller.load(
            url: baseURL.appendingPathComponent("video/hidden-gardens.mp4"),
            startPosition: nil,
            preferredAudioTrackID: nil,
            losslessAudio: false,
            spatialAudioLayout: nil,
            styledASSSubtitles: false,
            mediaIdentifier: "hidden-gardens",
            providerStreamIDsByFFIndex: [:],
            externalSubtitles: []
        )
        for _ in 0..<150 {
            if controller.position > 1 || controller.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(controller.errorMessage)
        XCTAssertGreaterThan(controller.position, 1, "The real playback engine must advance")
        controller.seek(to: 45)
        for _ in 0..<100 {
            if controller.position >= 44 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(controller.position, 44)
        controller.setMaximumVolume(0.2)
        XCTAssertEqual(controller.maximumVolume, 0.2, accuracy: 0.001)
        controller.pause()
        for _ in 0..<30 {
            if controller.isPaused { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(controller.isPaused)
    }

    // MARK: - Helpers

    /// A `SessionManager` on stores of its own: a throwaway defaults suite and an in-memory secret store. The sample
    /// account never reaches the Keychain or the family's preferences, and the sample library's first-launch condition
    /// (no account yet) holds whatever the simulator has stored.
    private func makeIsolatedSession(accounts: [(MediaAccount, String)] = []) throws -> SessionManager {
        let suite = "PlinxDemoFixtureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let accountStore = AccountStore(userDefaults: defaults, secureStore: DemoFixtureTestSecureStore())
        for (account, token) in accounts {
            try accountStore.save(account, token: token)
        }
        let settings = SettingsManager(userDefaults: defaults)
        return SessionManager(
            settingsManager: settings,
            favoritesStore: FavoritesStore(userDefaults: defaults),
            trackSelectionCoordinator: TrackSelectionCoordinator(
                store: TrackSelectionStore(userDefaults: defaults),
                settingsManager: settings
            ),
            versionSelectionStore: MediaVersionSelectionStore(userDefaults: defaults),
            accountStore: accountStore,
            profileStore: ProfileStore(userDefaults: defaults)
        )
    }

    private func waitForHydration(of session: SessionManager) async throws {
        var attempts = 0
        while session.status == .hydrating, attempts < 100 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotEqual(session.status, .hydrating, "Session did not finish hydrating")
    }

    /// Starts the sample library on an isolated session through the production bootstrap, `ServerRegistry` and
    /// `SafeMediaServices`, and returns the session with the sample server's services. Callers stop it.
    private func startSampleLibrary() async throws -> (SessionManager, MediaServices) {
        let session = try makeIsolatedSession()
        try await waitForHydration(of: session)
        XCTAssertEqual(session.status, .needsAccount)
        await DemoFixtureBootstrap.start(sessionManager: session)
        XCTAssertEqual(session.status, .ready)
        XCTAssertTrue(DemoFixtureBootstrap.isDemoSession(session))
        let services = try XCTUnwrap(session.registry.services(for: DemoFixtureBootstrap.server))
        return (session, services)
    }
}

/// Secrets of an isolated test session; nothing reaches the Keychain.
private final class DemoFixtureTestSecureStore: SecureStore {
    private var values: [String: String] = [:]

    func string(forKey key: String) throws -> String? {
        values[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    func deleteValue(forKey key: String) throws {
        values[key] = nil
    }
}
