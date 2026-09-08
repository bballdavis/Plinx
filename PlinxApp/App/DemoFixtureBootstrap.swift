import Foundation

/// Starts the credential-free review experience against a deterministic,
/// in-process Plex-shaped transport. The transport is deliberately scoped to
/// an invalid host so it cannot intercept a real Plex server or cloud request.
enum DemoFixtureBootstrap {
    static let serverHost = "demo.plinx.invalid"
    static let serverToken = "plinx-synthetic-review-token"

    static var isActive: Bool {
        DemoFixtureURLProtocol.isActive
    }

    @MainActor
    static func start(
        sessionManager: SessionManager,
        context: PlexAPIContext,
    ) async {
        #if os(tvOS)
        // App Review's credential-free path is currently shipped for iPhone
        // and iPad. Do not activate it on tvOS, where selecting a server also
        // updates Top Shelf session state.
        return
        #else
        guard let serverURL = URL(string: "http://\(serverHost)") else { return }

        DemoFixtureURLProtocol.activate()

        let connection = PlexCloudResource.Connection(
            scheme: "http",
            address: serverHost,
            port: 80,
            uri: serverURL,
            isLocal: true,
            isRelay: false,
            isIPv6: false,
        )
        let resource = PlexCloudResource(
            name: "Plinx Demo Library",
            clientIdentifier: "plinx-demo-library",
            accessToken: serverToken,
            connections: [connection],
        )

        // This existing Strimr seam establishes a normal ready session and
        // reloads LibraryStore, but does not persist the synthetic token.
        await sessionManager.bootstrapDirectServerSession(
            resource: resource,
            token: serverToken,
            setAsDefault: false,
        )

        if case .ready = sessionManager.status {
            return
        }

        DemoFixtureURLProtocol.deactivate()
        context.reset()
        #endif
    }

    static func stop() {
        DemoFixtureURLProtocol.deactivate()
    }
}

/// URLSession.shared is used by the vendored Plex repositories, so a scoped
/// URLProtocol lets the demo reuse the production SessionManager, LibraryStore,
/// browse, metadata, search, artwork, and playback-authorization paths without
/// changing Strimr sources or starting a host process.
final class DemoFixtureURLProtocol: URLProtocol {
    private static let stateLock = NSLock()
    private static var active = false

    static var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return active
    }

    static func activate() {
        stateLock.lock()
        active = true
        stateLock.unlock()
        URLProtocol.registerClass(self)
    }

    static func deactivate() {
        stateLock.lock()
        active = false
        stateLock.unlock()
        URLProtocol.unregisterClass(self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard isActive else { return false }
        return request.url?.host?.caseInsensitiveCompare(DemoFixtureBootstrap.serverHost) == .orderedSame
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestURL = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = DemoFixtureCatalog.response(for: request)
        let httpResponse = HTTPURLResponse(
            url: requestURL,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": response.mimeType,
                "Content-Length": String(response.data.count),
                "Cache-Control": "no-store",
            ],
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum DemoFixtureCatalog {
    private struct Record {
        let id: String
        let title: String
        let rating: String
        let year: Int
        let summary: String
        let type: String
        let sectionID: Int
        let viewOffset: Int?
    }

    private static let movies = [
        Record(id: "moonbound", title: "Moonbound", rating: "PG", year: 2026, summary: "A family science adventure.", type: "movie", sectionID: 1, viewOffset: 1_920_000),
        Record(id: "cloud-chasers", title: "Cloud Chasers", rating: "PG", year: 2025, summary: "Young weather watchers follow a summer storm.", type: "movie", sectionID: 1, viewOffset: 1_380_000),
        Record(id: "big-build", title: "The Big Build", rating: "PG", year: 2024, summary: "Friends transform an empty lot into a community workshop.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "hidden-gardens", title: "Hidden Gardens", rating: "G", year: 2023, summary: "A gentle tour of surprising gardens around the world.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "robot-club", title: "Robot Club", rating: "PG", year: 2026, summary: "A school robotics team learns to build together.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "lighthouse-map", title: "The Lighthouse Map", rating: "PG", year: 2025, summary: "Siblings follow clues along a quiet coast.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "paper-airship", title: "The Paper Airship", rating: "G", year: 2024, summary: "A classroom invention takes an unexpected journey.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "river-trail", title: "The River Trail", rating: "PG", year: 2026, summary: "Friends learn to read a landscape together.", type: "movie", sectionID: 1, viewOffset: nil),
    ]

    private static let shows = [
        Record(id: "space-camp", title: "Space Camp", rating: "TV-PG", year: 2026, summary: "Young explorers train for a mission beyond Earth.", type: "show", sectionID: 2, viewOffset: 630_000),
        Record(id: "kitchen-lab", title: "Kitchen Lab", rating: "TV-G", year: 2025, summary: "Every recipe becomes a friendly science experiment.", type: "show", sectionID: 2, viewOffset: 420_000),
        Record(id: "wild-neighbors", title: "Wild Neighbors", rating: "TV-PG", year: 2024, summary: "Families discover the animals living close to home.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "makers-next-door", title: "Makers Next Door", rating: "TV-G", year: 2025, summary: "Creative neighbors share practical projects.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "junior-rangers", title: "Junior Rangers", rating: "TV-G", year: 2026, summary: "Young naturalists care for a neighborhood park.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "story-station", title: "Story Station", rating: "TV-PG", year: 2025, summary: "A book club turns stories into weekend adventures.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "music-room", title: "The Music Room", rating: "TV-G", year: 2024, summary: "Friends explore instruments and sounds.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "market-day", title: "Market Day", rating: "TV-PG", year: 2026, summary: "A community market becomes a lesson in teamwork.", type: "show", sectionID: 2, viewOffset: nil),
    ]

    private static let otherVideos = [
        Record(id: "bridge-basics", title: "How Bridges Work", rating: "PG", year: 2026, summary: "A friendly look at bridge design.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "backyard-sky", title: "Backyard Astronomy", rating: "PG", year: 2026, summary: "A beginner guide to the night sky.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "tiny-garden", title: "Make a Tiny Garden", rating: "G", year: 2026, summary: "A small growing project for families.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "science-sound", title: "The Science of Sound", rating: "PG", year: 2026, summary: "Experiments with rhythm and vibration.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "friendly-dragons", title: "Drawing Friendly Dragons", rating: "G", year: 2026, summary: "A playful step-by-step drawing lesson.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "bird-feeder", title: "Build a Bird Feeder", rating: "G", year: 2026, summary: "A simple project for welcoming backyard birds.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "cloud-journal", title: "Start a Cloud Journal", rating: "PG", year: 2026, summary: "Learn to notice and record changing skies.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "paper-circuits", title: "Make a Paper Circuit", rating: "PG", year: 2026, summary: "Light up a drawing with a beginner circuit.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "bread-science", title: "The Science of Bread", rating: "G", year: 2026, summary: "See how simple ingredients change as dough rises.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "map-compass", title: "Maps and Compasses", rating: "PG", year: 2026, summary: "Practice basic navigation on a family walk.", type: "movie", sectionID: 3, viewOffset: nil),
    ]

    private static var allRecords: [Record] {
        movies + shows + otherVideos
    }

    private static let artworkPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    static func response(for request: URLRequest) -> DemoFixtureResponse {
        guard let url = request.url else {
            return DemoFixtureResponse(statusCode: 400, mimeType: "application/json", data: jsonData(["error": "missing URL"]))
        }

        let path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let method = request.httpMethod?.uppercased() ?? "GET"

        switch (method, path) {
        case (_, "/"):
            return json(["MediaContainer": [:]])
        case (_, "/library/sections/all"):
            return json([
                "MediaContainer": [
                    "size": 3,
                    "Directory": [
                        ["agent": "tv.plex.agents.movie", "key": "1", "type": "movie", "title": "Family Movies"],
                        ["agent": "tv.plex.agents.series", "key": "2", "type": "show", "title": "Family TV"],
                        ["agent": "tv.plex.agents.none", "key": "3", "type": "movie", "title": "Learning Videos"],
                    ],
                ],
            ])
        case (_, "/hubs/continueWatching"):
            let continueItems = [shows[0], shows[1], movies[0], shows[2], movies[1], shows[4]].map(itemJSON)
            return hubResponse(title: "Continue Watching", identifier: "continueWatching", items: continueItems)
        case (_, "/hubs/promoted"):
            let items = (Array(movies.prefix(6)) + Array(shows.prefix(6))).map(itemJSON)
            return hubResponse(title: "Recently Added", identifier: "recentlyAdded", items: items)
        case (_, let value) where value.hasPrefix("/hubs/sections/"):
            let sectionID = value.split(separator: "/").last.flatMap { Int($0) } ?? 1
            let records = recordsForSection(sectionID)
            return hubResponse(title: "Recommended", identifier: "recommended-\(sectionID)", items: records.map(itemJSON))
        case (_, "/library/search"):
            let searchText = query.first(where: { $0.name == "query" })?.value?.lowercased() ?? ""
            let results = allRecords
                .filter { searchText.isEmpty || $0.title.lowercased().contains(searchText) }
                .map { ["score": 1.0, "Metadata": itemJSON($0)] }
            return json(["MediaContainer": ["size": results.count, "SearchResult": results]])
        case (_, let value) where value.hasPrefix("/library/sections/") && value.hasSuffix("/all"):
            let components = value.split(separator: "/")
            let sectionID = components.dropFirst(2).first.flatMap { Int($0) } ?? 1
            let records = recordsForSection(sectionID)
            return itemContainer(records.map(itemJSON))
        case (_, let value) where value.hasPrefix("/library/sections/") && value.hasSuffix("/collections"):
            return itemContainer([])
        case (_, let value) where value.hasPrefix("/library/metadata/") && value.hasSuffix("/related"):
            let rawID = String(value.dropFirst("/library/metadata/".count))
            let id = String(rawID.dropLast("/related".count))
            let source = allRecords.first(where: { $0.id == id })
            let related = allRecords
                .filter { $0.id != id && $0.type == source?.type }
                .prefix(6)
                .map(itemJSON)
            return hubResponse(title: "More Like This", identifier: "related-\(id)", items: related)
        case (_, let value) where value.hasPrefix("/library/metadata/"):
            return metadataResponse(for: String(value.dropFirst("/library/metadata/".count)))
        case (_, let value) where value.hasPrefix("/library/collections/") || value.hasPrefix("/playlists"):
            return itemContainer([])
        case (_, "/photo/:/transcode"):
            return DemoFixtureResponse(statusCode: 200, mimeType: "image/png", data: artworkPNG)
        case (_, let value) where value.hasPrefix("/artwork/"):
            return DemoFixtureResponse(statusCode: 200, mimeType: "image/png", data: artworkPNG)
        case ("POST", "/playQueues"):
            let requestedID = query.first(where: { $0.name == "uri" })?.value?.split(separator: "/").last.map(String.init)
            let selected = allRecords.first(where: { $0.id == requestedID }) ?? movies[0]
            let queueItems = [selected].map { itemJSON($0).merging(["playQueueItemID": 1]) { current, _ in current }
            }
            return json([
                "MediaContainer": [
                    "size": queueItems.count,
                    "playQueueID": 1,
                    "playQueueSelectedItemID": 1,
                    "playQueueSelectedMetadataItemID": selected.id,
                    "playQueueTotalCount": queueItems.count,
                    "playQueueVersion": 1,
                    "Metadata": queueItems,
                ],
            ])
        case (_, let value) where value.hasPrefix("/playQueues/"):
            return json(["MediaContainer": ["playQueueID": 1, "playQueueTotalCount": 0, "Metadata": []]])
        case (_, "/:/timeline"), (_, "/:/scrobble"), (_, "/:/unscrobble"), (_, "/library/parts/1"):
            return json(["MediaContainer": [:]])
        default:
            return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "demo fixture endpoint not found", "path": path]))
        }
    }

    private static func recordsForSection(_ sectionID: Int) -> [Record] {
        switch sectionID {
        case 1: movies
        case 2: shows
        case 3: otherVideos
        default: []
        }
    }

    private static func itemJSON(_ record: Record) -> [String: Any] {
        var item: [String: Any] = [
            "ratingKey": record.id,
            "key": "/library/metadata/\(record.id)",
            "guid": "plex://fixture/\(record.id)",
            "librarySectionID": record.sectionID,
            "type": record.type,
            "title": record.title,
            "summary": record.summary,
            "thumb": "/artwork/poster/\(record.id).png",
            "art": "/artwork/backdrop/\(record.id).png",
            "year": record.year,
            "duration": record.type == "show" ? 1_560_000 : 6_120_000,
            "contentRating": record.rating,
            "studio": "Plinx Fixture Studio",
            "tagline": "Curiosity starts close to home.",
            "audienceRating": 8.4,
            "rating": 8.1,
            "Genre": [["tag": "Family"], ["tag": "Adventure"]],
            "Role": [["id": 1, "tag": "Avery North"], ["id": 2, "tag": "Jordan Vale"]],
            "Media": [[
                "id": 1,
                "videoResolution": "1080",
                "Part": [["id": 1, "key": "/video/\(record.id).mp4", "size": 1]],
            ]],
        ]
        if let viewOffset = record.viewOffset {
            item["viewOffset"] = viewOffset
        }
        if record.type == "show" {
            item["childCount"] = 2
            item["leafCount"] = 4
            item["viewedLeafCount"] = 1
        }
        return item
    }

    private static func metadataResponse(for rawID: String) -> DemoFixtureResponse {
        let id = rawID.split(separator: "/").first.map(String.init) ?? rawID
        if rawID.hasSuffix("/children") {
            let parentID = id
            if let show = shows.first(where: { $0.id == parentID }) {
                return itemContainer((1...2).map { seasonJSON(show: show, index: $0) })
            }
            if let season = seasonIDParts(parentID) {
                return itemContainer((1...2).map { episodeJSON(showID: season.showID, season: season.index, episode: $0) })
            }
            return itemContainer([])
        }
        if rawID.hasSuffix("/grandchildren") {
            guard let show = shows.first(where: { $0.id == id }) else { return itemContainer([]) }
            let episodes = (1...2).flatMap { season in
                (1...2).map { episodeJSON(showID: show.id, season: season, episode: $0) }
            }
            return itemContainer(episodes)
        }
        if let record = allRecords.first(where: { $0.id == id }) {
            return itemContainer([itemJSON(record)])
        }
        if let season = seasonIDParts(id) {
            return itemContainer([seasonJSON(show: shows.first(where: { $0.id == season.showID }) ?? shows[0], index: season.index)])
        }
        if let episode = episodeIDParts(id) {
            return itemContainer([episodeJSON(showID: episode.showID, season: episode.season, episode: episode.episode)])
        }
        return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "unknown demo media"]))
    }

    private static func seasonIDParts(_ id: String) -> (showID: String, index: Int)? {
        let parts = id.split(separator: "-")
        guard parts.count >= 3, parts[parts.count - 2] == "season", let index = Int(parts.last!) else { return nil }
        return (parts.dropLast(2).joined(separator: "-"), index)
    }

    private static func episodeIDParts(_ id: String) -> (showID: String, season: Int, episode: Int)? {
        let parts = id.split(separator: "-")
        guard parts.count >= 5,
              parts[parts.count - 4] == "season",
              parts[parts.count - 2] == "e",
              let season = Int(parts[parts.count - 3]),
              let episode = Int(parts.last!)
        else { return nil }
        return (parts.dropLast(4).joined(separator: "-"), season, episode)
    }

    private static func seasonJSON(show: Record, index: Int) -> [String: Any] {
        [
            "ratingKey": "\(show.id)-season-\(index)",
            "key": "/library/metadata/\(show.id)-season-\(index)",
            "guid": "plex://fixture/\(show.id)-season-\(index)",
            "type": "season",
            "title": "Season \(index)",
            "parentRatingKey": show.id,
            "parentTitle": show.title,
            "parentIndex": index,
            "thumb": "/artwork/poster/\(show.id).png",
            "art": "/artwork/backdrop/\(show.id).png",
            "contentRating": show.rating,
            "childCount": 2,
        ]
    }

    private static func episodeJSON(showID: String, season: Int, episode: Int) -> [String: Any] {
        let show = shows.first(where: { $0.id == showID }) ?? shows[0]
        let id = "\(showID)-season-\(season)-e-\(episode)"
        return [
            "ratingKey": id,
            "key": "/library/metadata/\(id)",
            "guid": "plex://fixture/\(id)",
            "type": "episode",
            "title": "Episode \(episode)",
            "summary": "A fictional episode from the Plinx review fixture.",
            "parentRatingKey": "\(showID)-season-\(season)",
            "parentTitle": "Season \(season)",
            "parentIndex": season,
            "grandparentRatingKey": showID,
            "grandparentTitle": show.title,
            "grandparentThumb": "/artwork/poster/\(showID).png",
            "grandparentArt": "/artwork/backdrop/\(showID).png",
            "index": episode,
            "duration": 1_560_000,
            "contentRating": show.rating,
            "thumb": "/artwork/poster/\(showID).png",
            "art": "/artwork/backdrop/\(showID).png",
            "Media": [[
                "id": 1,
                "videoResolution": "1080",
                "Part": [["id": 1, "key": "/video/\(id).mp4", "size": 1]],
            ]],
        ]
    }

    private static func hubResponse(title: String, identifier: String, items: [[String: Any]]) -> DemoFixtureResponse {
        json([
            "MediaContainer": [
                "size": 1,
                "Hub": [[
                    "hubKey": "/hubs/\(identifier)",
                    "key": "/hubs/\(identifier)",
                    "title": title,
                    "hubIdentifier": identifier,
                    "size": items.count,
                    "more": false,
                    "Metadata": items,
                ]],
            ],
        ])
    }

    private static func itemContainer(_ items: [[String: Any]]) -> DemoFixtureResponse {
        json(["MediaContainer": ["size": items.count, "totalSize": items.count, "Metadata": items]])
    }

    private static func json(_ object: Any) -> DemoFixtureResponse {
        DemoFixtureResponse(statusCode: 200, mimeType: "application/json", data: jsonData(object))
    }

    private static func jsonData(_ object: Any) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return data
    }
}

struct DemoFixtureResponse {
    let statusCode: Int
    let mimeType: String
    let data: Data
}
