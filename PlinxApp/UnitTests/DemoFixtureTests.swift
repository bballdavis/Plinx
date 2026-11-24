import Foundation
import PlinxCore
import UIKit
import XCTest
@testable import Plinx

@MainActor
final class DemoFixtureTests: XCTestCase {
    func testDemoServerIsLoopbackOnlyAndRequiresTheSyntheticToken() async throws {
        let server = DemoFixtureServer.shared
        let baseURL = try await server.start()
        defer { server.stop() }

        XCTAssertEqual(baseURL.host, "127.0.0.1")
        XCTAssertTrue(DemoFixtureBootstrap.isActive)

        let sectionsURL = baseURL.appendingPathComponent("library/sections/all")
        let (_, unauthorized) = try await URLSession.shared.data(from: sectionsURL)
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)

        var request = URLRequest(url: sectionsURL)
        request.setValue(DemoFixtureBootstrap.serverToken, forHTTPHeaderField: "X-Plex-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        var videoRequest = URLRequest(url: baseURL.appendingPathComponent("video/moonbound.mp4"))
        videoRequest.setValue(DemoFixtureBootstrap.serverToken, forHTTPHeaderField: "X-Plex-Token")
        videoRequest.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (videoData, videoResponse) = try await URLSession.shared.data(for: videoRequest)
        let http = try XCTUnwrap(videoResponse as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(videoData.count, 1_024)
        XCTAssertTrue(http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes 0-1023/") == true)
    }

    func testByteRangeParsing() {
        XCTAssertEqual(DemoFixtureServer.byteRange("bytes=0-99", length: 1_000), 0...99)
        XCTAssertEqual(DemoFixtureServer.byteRange("bytes=900-", length: 1_000), 900...999)
        XCTAssertEqual(DemoFixtureServer.byteRange("bytes=-100", length: 1_000), 900...999)
        XCTAssertEqual(DemoFixtureServer.byteRange("bytes=0-5000", length: 1_000), 0...999)
        XCTAssertNil(DemoFixtureServer.byteRange("bytes=2000-", length: 1_000))
        XCTAssertNil(DemoFixtureServer.byteRange("items=0-1", length: 1_000))
    }

    func testSectionsFixtureContainsThreeSafeLibraries() throws {
        let request = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/library/sections/all")!)
        let response = DemoFixtureCatalog.response(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let container = try XCTUnwrap(object["MediaContainer"] as? [String: Any])
        let sections = try XCTUnwrap(container["Directory"] as? [[String: Any]])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.compactMap { $0["title"] as? String }, ["Family Movies", "Family TV", "Learning Videos"])
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

    // MARK: - App Review coverage

    private func items(at path: String) throws -> [PlexItem] {
        let request = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)\(path)")!)
        let response = DemoFixtureCatalog.response(for: request)
        XCTAssertEqual(response.statusCode, 200, path)
        return try JSONDecoder().decode(PlexItemMediaContainer.self, from: response.data).mediaContainer.metadata ?? []
    }

    func testShippedDefaultControlsLeaveEveryLibraryPopulated() throws {
        // Mirrors the app's first-run defaults: Movies G, TV TV-Y, unrated hidden.
        let defaults = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)
        for sectionID in 1...3 {
            let visible = try items(at: "/library/sections/\(sectionID)/all")
                .filter { StrimrAdapter.isAllowed($0, policy: defaults) }
            XCTAssertGreaterThanOrEqual(visible.count, 5, "Section \(sectionID) should be browsable with default controls")
        }
    }

    func testRaisingCeilingsRevealsRestrictedFixtures() throws {
        let all = try (1...3).flatMap { try items(at: "/library/sections/\($0)/all") }
        let defaults = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)
        let permissive = SafetyPolicy.ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: true)

        let hiddenByDefault = Set(all.filter { !StrimrAdapter.isAllowed($0, policy: defaults) }.map(\.ratingKey))
        XCTAssertTrue(hiddenByDefault.isSuperset(of: ["summit-signal", "night-shift-academy", "workshop-tour"]))
        XCTAssertTrue(all.allSatisfy { StrimrAdapter.isAllowed($0, policy: permissive) })
        XCTAssertNil(all.first(where: { $0.ratingKey == "workshop-tour" })?.contentRating, "One fixture must model unrated media")
    }

    func testCollectionsAndPlaylistsDecodeWithMembers() throws {
        let collections = try items(at: "/library/sections/1/collections")
        XCTAssertGreaterThanOrEqual(collections.count, 2)
        XCTAssertTrue(collections.allSatisfy { $0.type == .collection })
        let firstCollection = try XCTUnwrap(collections.first)
        XCTAssertFalse(try items(at: "/library/collections/\(firstCollection.ratingKey)/children").isEmpty)

        let playlists = try items(at: "/playlists")
        let playlist = try XCTUnwrap(playlists.first)
        XCTAssertEqual(playlist.type, .playlist)
        let entries = try items(at: "/playlists/\(playlist.ratingKey)/items")
        XCTAssertTrue(entries.contains { $0.type == .episode })
        XCTAssertTrue(entries.contains { $0.type == .movie })
    }

    func testBrowseHonorsPlexPagingWithoutDuplicates() throws {
        func page(start: Int, size: Int) throws -> [String] {
            var request = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/library/sections/2/all")!)
            request.setValue(String(start), forHTTPHeaderField: "X-Plex-Container-Start")
            request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
            let response = DemoFixtureCatalog.response(for: request)
            return try JSONDecoder().decode(PlexItemMediaContainer.self, from: response.data).mediaContainer.metadata?.map(\.ratingKey) ?? []
        }
        let first = try page(start: 0, size: 4)
        let second = try page(start: 4, size: 4)
        let rest = try page(start: 8, size: 50)
        XCTAssertEqual(first.count, 4)
        XCTAssertTrue(Set(first).isDisjoint(with: second))
        XCTAssertEqual((first + second + rest).count, try items(at: "/library/sections/2/all").count)
        XCTAssertTrue(try page(start: 500, size: 10).isEmpty)
    }

    func testBrowseJumpIndexMatchesTitleOrder() throws {
        let request = URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/library/sections/1/firstCharacter")!)
        let response = DemoFixtureCatalog.response(for: request)
        let decoded = try JSONDecoder().decode(PlexFirstCharacterMediaContainer.self, from: response.data)
        let directory = try XCTUnwrap(decoded.mediaContainer.directory)
        XCTAssertEqual(directory.compactMap(\.key), directory.compactMap(\.key).sorted())
        XCTAssertEqual(directory.compactMap(\.size).reduce(0, +), try items(at: "/library/sections/1/all").count)
    }

    func testArtworkIsRenderedThroughTheTranscodeEndpoint() throws {
        var components = URLComponents(string: "http://\(DemoFixtureBootstrap.serverHost)/photo/:/transcode")!
        components.queryItems = [
            URLQueryItem(name: "url", value: "/artwork/poster/moonbound.png"),
            URLQueryItem(name: "width", value: "240"),
        ]
        let response = DemoFixtureCatalog.response(for: URLRequest(url: components.url!))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.mimeType, "image/jpeg")
        let image = try XCTUnwrap(UIImage(data: response.data))
        XCTAssertEqual(image.size.width / image.size.height, 2.0 / 3.0, accuracy: 0.01)
        XCTAssertGreaterThan(response.data.count, 4_000, "Artwork should be a real image, not a 1x1 placeholder")

        let backdrop = DemoFixtureCatalog.response(for: URLRequest(url: URL(string: "http://\(DemoFixtureBootstrap.serverHost)/artwork/backdrop/space-camp.png")!))
        XCTAssertEqual(backdrop.statusCode, 200)
        XCTAssertEqual(DemoFixtureArtwork.imageData(kind: .poster, id: "moonbound", title: "Moonbound"), response.data, "Artwork is deterministic and cached")
    }
}
