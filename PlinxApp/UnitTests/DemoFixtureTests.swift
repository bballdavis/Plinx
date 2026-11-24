import Foundation
import AVFoundation
import PlinxCore
import XCTest
@testable import Plinx

@MainActor
final class DemoFixtureTests: XCTestCase {
    func testDemoTransportIsScopedToSyntheticHost() {
        DemoFixtureURLProtocol.activate()
        defer { DemoFixtureURLProtocol.deactivate() }

        let demoRequest = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/library/sections/all")!)
        let realRequest = URLRequest(url: URL(string: "https://plex.tv/api/v2/user")!)
        let nearMatchRequest = URLRequest(url: URL(string: "http://notdemo.\(DemoFixtureBootstrap.serverHost)/library/sections/all")!)

        XCTAssertTrue(DemoFixtureURLProtocol.canInit(with: demoRequest))
        XCTAssertFalse(DemoFixtureURLProtocol.canInit(with: realRequest))
        XCTAssertFalse(DemoFixtureURLProtocol.canInit(with: nearMatchRequest))
    }

    func testSectionsFixtureIncludesDedicatedRatingLibraries() throws {
        let request = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/library/sections/all")!)
        let response = DemoFixtureCatalog.response(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let container = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let sections = try XCTUnwrap(container["Directory"] as? [[String: Any]])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(sections.count, 5)
        XCTAssertEqual(sections.compactMap { $0["title"] as? String }, ["Family Movies", "Family TV", "Learning Videos", "Rating Test Movies", "Rating Test TV"])
    }

    func testDemoHomeContainsContinueWatchingAndEnoughRows() throws {
        let request = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/hubs/continueWatching")!)
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
        var components = URLComponents(string: "http://\(DemoFixtureBootstrap.serverHost)/library/search")!
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
        let request = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/library/metadata/moonbound/related")!)
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
        var components = URLComponents(string: "http://\(DemoFixtureBootstrap.serverHost)/playQueues")!
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
        var request = URLRequest(url: URL(string: "http://demo.plinx.invalid/playQueues?uri=/library/metadata/\(id)")!)
        request.httpMethod = "POST"
        let response = try JSONDecoder().decode(PlexPlayQueueResponse.self, from: DemoFixtureCatalog.response(for: request).data)
        XCTAssertEqual(response.mediaContainer.metadata?.first?.ratingKey, id)
        let videoRequest = URLRequest(url: URL(string: "http://demo.plinx.invalid/video/\(id).mp4")!)
        let video = DemoFixtureCatalog.response(for: videoRequest)
        XCTAssertEqual(video.mimeType, "video/mp4")
        XCTAssertEqual(video.data.count, DemoSampleMedia.byteCount(isEpisode: true))
        let unknown = URLRequest(url: URL(string: "http://demo.plinx.invalid/video/not-an-item.mp4")!)
        XCTAssertEqual(DemoFixtureCatalog.response(for: unknown).statusCode, 404)
    }

    func testMixedCollectionActuallyExercisesSafetyFiltering() throws {
        let request = URLRequest(url: URL(string: "http://demo.plinx.invalid/library/collections/demo-mix/children")!)
        let response = try JSONDecoder().decode(PlexItemMediaContainer.self, from: DemoFixtureCatalog.response(for: request).data)
        let items = try XCTUnwrap(response.mediaContainer.metadata)
        XCTAssertEqual(items.count, 4)
        let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        let permitted = items.filter { PlinxContentAuthorization.isAllowed(MediaItem(plexItem: $0), policy: policy) }
        XCTAssertEqual(Set(permitted.map(\.ratingKey)), ["moonbound", "hidden-gardens"])
    }

    func testRatingLibrariesFilterEveryCeilingIndependentlyThroughProductionLoader() async throws {
        defer { DemoFixtureBootstrap.stop() }
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let session = SessionManager(context: context, libraryStore: store)
        for _ in 0..<100 where session.status == .hydrating {
            try await Task.sleep(for: .milliseconds(50))
        }
        await DemoFixtureBootstrap.start(sessionManager: session, context: context)
        XCTAssertEqual(session.status, .ready)
        let movies = try XCTUnwrap(store.libraries.first(where: { $0.sectionId == 4 }))
        let television = try XCTUnwrap(store.libraries.first(where: { $0.sectionId == 5 }))
        let loader = LibraryCatalogLoader(context: context)
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
                    let policy = SafetyPolicy.ratingOnly(maxMovie: movieCeiling, maxTV: tvCeiling, allowUnrated: allowUnrated)
                    let movieResult = try await loader.recentItems(for: movies, limit: 20, policy: policy)
                    let tvResult = try await loader.recentItems(for: television, limit: 20, policy: policy)
                    let expectedMovies = (movieIDs + (allowUnrated ? ["unrated"] : [])).map { "rating-movie-\($0)" }
                    let expectedTV = (tvIDs + (allowUnrated ? ["unrated"] : [])).map { "rating-tv-\($0)" }
                    XCTAssertEqual(Set(movieResult.items.map(\.id)), Set(expectedMovies), "Movie \(movieCeiling), TV \(tvCeiling), unrated \(allowUnrated)")
                    XCTAssertEqual(Set(tvResult.items.map(\.id)), Set(expectedTV), "Movie \(movieCeiling), TV \(tvCeiling), unrated \(allowUnrated)")
                }
            }
        }
        // Lower again after the permissive cases; prior access must not stick.
        let resetPolicy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        let resetMovies = try await loader.recentItems(for: movies, limit: 20, policy: resetPolicy)
        XCTAssertEqual(Set(resetMovies.items.map(\.id)), ["rating-movie-g", "rating-movie-pg"])
    }

    func testTVRatingExamplesPropagateToSeasonsEpisodesAndPlaybackAuthorization() throws {
        for (key, rating) in [("tvy", "TV-Y"), ("tvy7", "TV-Y7"), ("tvg", "TV-G"), ("tvpg", "TV-PG"), ("tv14", "TV-14"), ("tvma", "TV-MA"), ("unrated", "")] {
            let showID = "rating-tv-\(key)"
            for id in [showID, "\(showID)-season-1", "\(showID)-season-1-e-1"] {
                let request = URLRequest(url: URL(string: "http://demo.plinx.invalid/library/metadata/\(id)")!)
                let result = DemoFixtureCatalog.response(for: request)
                let response = try JSONDecoder().decode(PlexItemMediaContainer.self, from: result.data)
                let item = try XCTUnwrap(response.mediaContainer.metadata?.first)
                XCTAssertEqual(item.contentRating ?? "", rating)
                XCTAssertEqual(item.librarySectionID, 5)
                let policy = SafetyPolicy.ratingOnly(maxMovie: .r, maxTV: .tvPg, allowUnrated: false)
                XCTAssertEqual(PlinxContentAuthorization.isAllowed(item, policy: policy), !["tv14", "tvma", "unrated"].contains(key))
            }
            let episodesRequest = URLRequest(url: URL(string: "http://demo.plinx.invalid/library/metadata/\(showID)/grandchildren")!)
            let episodes = try JSONDecoder().decode(PlexItemMediaContainer.self, from: DemoFixtureCatalog.response(for: episodesRequest).data)
            XCTAssertEqual(episodes.mediaContainer.metadata?.count, 4)
        }
        let raw = URLRequest(url: URL(string: "http://demo.plinx.invalid/library/metadata/rating-movie-unrated")!)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: DemoFixtureCatalog.response(for: raw).data) as? [String: Any])
        let container = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let items = try XCTUnwrap(container["Metadata"] as? [[String: Any]])
        XCTAssertNil(items.first?["contentRating"], "Unrated samples must exercise missing rating metadata")
    }

    func testProductionDownloadCompletesAndRemainsPlayableWithoutServer() async throws {
        defer { DemoFixtureBootstrap.stop() }
        let context = PlexAPIContext()
        let session = SessionManager(context: context, libraryStore: LibraryStore(context: context))
        for _ in 0..<100 where session.status == .hydrating {
            try await Task.sleep(for: .milliseconds(50))
        }
        await DemoFixtureBootstrap.start(sessionManager: session, context: context)
        XCTAssertEqual(session.status, .ready)
        let identity = try XCTUnwrap(session.plinxDownloadOwnerIdentity)
        let manager = try XCTUnwrap(DownloadManager.shared)
        let suite = "PlinxDemoDownloadTest-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owners = DownloadOwnershipStore(defaults: defaults)
        let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        manager.configurePlinxEnrollment(identity: identity, safetyPolicy: policy, ownershipStore: owners, sessionManager: session)
        var downloaded: [(DownloadItem, URL)] = []
        for ratingKey in ["hidden-gardens", "space-camp-season-1-e-2"] {
            let ids = await manager.enqueueItem(ratingKey: ratingKey, context: context)
            let id = try XCTUnwrap(ids.first)
            for _ in 0..<200 {
                if manager.items.first(where: { $0.id == id })?.status == .completed { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let item = try XCTUnwrap(manager.items.first(where: { $0.id == id }))
            XCTAssertEqual(item.status, .completed, item.errorMessage ?? "Download did not finish")
            let file = try XCTUnwrap(manager.localVideoURL(for: item))
            XCTAssertEqual(try Data(contentsOf: file), DemoSampleMedia.data(isEpisode: ratingKey != "hidden-gardens"))
            XCTAssertEqual(DownloadAccessPolicy(safetyPolicy: policy, currentIdentity: identity, ownershipStore: owners).decision(for: item), .allowed)
            let personalIdentity = DownloadOwnerIdentity(serverIdentifier: "personal-server", profileIdentifier: "parent")
            XCTAssertNotEqual(DownloadAccessPolicy(safetyPolicy: policy, currentIdentity: personalIdentity, ownershipStore: owners).decision(for: item), .allowed)
            downloaded.append((item, file))
        }
        let priorIdentity = DownloadOwnerIdentity(serverIdentifier: "personal", profileIdentifier: "parent")
        let persistence = InMemoryOfflineSessionPersistence(snapshot: OfflineSessionSnapshot(identity: priorIdentity, serverName: "Personal"))
        let access = PlinxSessionAccessCoordinator(persistence: persistence)
        access.recordReadySession(sessionManager: session)
        XCTAssertEqual(access.snapshot?.identity, priorIdentity)
        DemoFixtureBootstrap.stop()
        XCTAssertNil(session.plinxDownloadOwnerIdentity)
        for (item, file) in downloaded {
            let duration = try await AVURLAsset(url: file).load(.duration)
            XCTAssertEqual(duration.seconds, 90, accuracy: 0.1)
            await manager.delete(item)
        }
        await session.signOut()
        manager.configureEnrollmentContextProvider { nil }
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
        controller.load(url: baseURL.appendingPathComponent("video/hidden-gardens.mp4"),
                        startPosition: nil, preferredAudioTrackID: nil, losslessAudio: false)
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

}
