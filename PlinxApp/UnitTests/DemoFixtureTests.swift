import Foundation
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
}
