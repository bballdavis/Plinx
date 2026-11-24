import Foundation

/// Starts the credential-free review experience against deterministic,
/// fictional Plex-shaped fixtures served by `DemoFixtureServer` on the loopback
/// interface. Nothing is fetched from or sent to Plex or any other host.
enum DemoFixtureBootstrap {
    static let serverHost = DemoFixtureServer.loopbackHost
    static let serverToken = "plinx-synthetic-review-token"

    static var isActive: Bool {
        DemoFixtureServer.shared.isRunning
    }

    @MainActor
    static func start(
        sessionManager: SessionManager,
        context: PlexAPIContext,
    ) async {
        guard let serverURL = try? await DemoFixtureServer.shared.start(),
              let port = serverURL.port
        else {
            DemoFixtureServer.shared.stop()
            return
        }

        let connection = PlexCloudResource.Connection(
            scheme: "http",
            address: serverHost,
            port: port,
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
        // reloads LibraryStore, but does not persist the synthetic token or
        // make the demo the default server. tvOS: SessionManager mirrors the
        // token into Top Shelf storage only when the bundle declares
        // TopShelfKeychainAccessGroup; Plinx ships no Top Shelf extension.
        await sessionManager.bootstrapDirectServerSession(
            resource: resource,
            token: serverToken,
            setAsDefault: false,
        )

        if case .ready = sessionManager.status {
            return
        }

        DemoFixtureServer.shared.stop()
        context.reset()
    }

    static func stop() {
        DemoFixtureServer.shared.stop()
    }

    /// UI-test-only shortcut (`--ui-testing` + `PLINX_UI_TEST_MODE=demo`) that
    /// enters the same demo path as the connection screen's demo action, so
    /// tvOS remote walkthroughs and screenshots start from a known library.
    static let uiTestMode = "demo"

    @MainActor
    static func bootstrapForUITestIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String],
        sessionManager: SessionManager,
        context: PlexAPIContext,
    ) {
        guard arguments.contains("--ui-testing"),
              environment["PLINX_UI_TEST_MODE"] == uiTestMode
        else { return }

        Task { @MainActor in
            while sessionManager.status == .hydrating {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await start(sessionManager: sessionManager, context: context)
        }
    }
}

enum DemoFixtureCatalog {
    private struct Record {
        let id: String
        let title: String
        /// `nil` models unrated media, which the default content controls hide.
        let rating: String?
        let year: Int
        let summary: String
        let type: String
        let sectionID: Int
        let viewOffset: Int?
    }

    // Ratings are spread across the ceilings parents control. With the shipped
    // defaults (Movies G, TV TV-Y, unrated hidden) every library still has a
    // full shelf; raising a ceiling or allowing unrated media visibly adds
    // titles. Keep docs/release/app-store.md's reviewer table in sync.
    private static let movies = [
        Record(id: "moonbound", title: "Moonbound", rating: "G", year: 2026, summary: "A family science adventure.", type: "movie", sectionID: 1, viewOffset: 48_000),
        Record(id: "cloud-chasers", title: "Cloud Chasers", rating: "G", year: 2025, summary: "Young weather watchers follow a summer storm.", type: "movie", sectionID: 1, viewOffset: 30_000),
        Record(id: "big-build", title: "The Big Build", rating: "PG", year: 2024, summary: "Friends transform an empty lot into a community workshop.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "hidden-gardens", title: "Hidden Gardens", rating: "G", year: 2023, summary: "A gentle tour of surprising gardens around the world.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "robot-club", title: "Robot Club", rating: "G", year: 2026, summary: "A school robotics team learns to build together.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "lighthouse-map", title: "The Lighthouse Map", rating: "PG", year: 2025, summary: "Siblings follow clues along a quiet coast.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "paper-airship", title: "The Paper Airship", rating: "G", year: 2024, summary: "A classroom invention takes an unexpected journey.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "river-trail", title: "The River Trail", rating: "PG", year: 2026, summary: "Friends learn to read a landscape together.", type: "movie", sectionID: 1, viewOffset: nil),
        // PG-13: visible only after a parent raises Movies to PG-13 or higher.
        Record(id: "summit-signal", title: "Summit Signal", rating: "PG-13", year: 2026, summary: "Teen climbers race a mountain storm to reach a stranded weather station.", type: "movie", sectionID: 1, viewOffset: nil),
    ]

    private static let shows = [
        Record(id: "space-camp", title: "Space Camp", rating: "TV-Y", year: 2026, summary: "Young explorers train for a mission beyond Earth.", type: "show", sectionID: 2, viewOffset: 66_000),
        Record(id: "kitchen-lab", title: "Kitchen Lab", rating: "TV-Y", year: 2025, summary: "Every recipe becomes a friendly science experiment.", type: "show", sectionID: 2, viewOffset: 42_000),
        Record(id: "wild-neighbors", title: "Wild Neighbors", rating: "TV-Y", year: 2024, summary: "Families discover the animals living close to home.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "makers-next-door", title: "Makers Next Door", rating: "TV-G", year: 2025, summary: "Creative neighbors share practical projects.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "junior-rangers", title: "Junior Rangers", rating: "TV-Y", year: 2026, summary: "Young naturalists care for a neighborhood park.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "story-station", title: "Story Station", rating: "TV-Y7", year: 2025, summary: "A book club turns stories into weekend adventures.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "music-room", title: "The Music Room", rating: "TV-Y", year: 2024, summary: "Friends explore instruments and sounds.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "market-day", title: "Market Day", rating: "TV-PG", year: 2026, summary: "A community market becomes a lesson in teamwork.", type: "show", sectionID: 2, viewOffset: nil),
        // TV-14: visible only after a parent raises TV to TV-14 or higher.
        Record(id: "night-shift-academy", title: "Night Shift Academy", rating: "TV-14", year: 2025, summary: "Older students run a late-night campus radio station.", type: "show", sectionID: 2, viewOffset: nil),
    ]

    private static let otherVideos = [
        Record(id: "bridge-basics", title: "How Bridges Work", rating: "G", year: 2026, summary: "A friendly look at bridge design.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "backyard-sky", title: "Backyard Astronomy", rating: "G", year: 2026, summary: "A beginner guide to the night sky.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "tiny-garden", title: "Make a Tiny Garden", rating: "G", year: 2026, summary: "A small growing project for families.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "science-sound", title: "The Science of Sound", rating: "G", year: 2026, summary: "Experiments with rhythm and vibration.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "friendly-dragons", title: "Drawing Friendly Dragons", rating: "G", year: 2026, summary: "A playful step-by-step drawing lesson.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "bird-feeder", title: "Build a Bird Feeder", rating: "G", year: 2026, summary: "A simple project for welcoming backyard birds.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "cloud-journal", title: "Start a Cloud Journal", rating: "TV-Y", year: 2026, summary: "Learn to notice and record changing skies.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "paper-circuits", title: "Make a Paper Circuit", rating: "PG", year: 2026, summary: "Light up a drawing with a beginner circuit.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "bread-science", title: "The Science of Bread", rating: "G", year: 2026, summary: "See how simple ingredients change as dough rises.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "map-compass", title: "Maps and Compasses", rating: "G", year: 2026, summary: "Practice basic navigation on a family walk.", type: "movie", sectionID: 3, viewOffset: nil),
        // Unrated: hidden until a parent allows unrated media.
        Record(id: "workshop-tour", title: "Workshop Tour", rating: nil, year: 2026, summary: "An unrated walk through a community makerspace.", type: "movie", sectionID: 3, viewOffset: nil),
    ]

    /// Every fixture plays the same bundled, original two-minute clip, so
    /// metadata durations and resume points match real playback.
    static let clipDurationMS = 120_000

    private static var allRecords: [Record] {
        movies + shows + otherVideos
    }

    private struct Grouping {
        let id: String
        let title: String
        let summary: String
        let sectionID: Int
        let memberIDs: [String]
    }

    private static let collections = [
        Grouping(id: "collection-sky-stories", title: "Sky Stories", summary: "Adventures that look up.", sectionID: 1, memberIDs: ["moonbound", "cloud-chasers", "paper-airship", "summit-signal"]),
        Grouping(id: "collection-build-together", title: "Build Together", summary: "Makers, tinkerers, and team projects.", sectionID: 1, memberIDs: ["big-build", "robot-club", "river-trail"]),
        Grouping(id: "collection-backyard-science", title: "Backyard Science", summary: "Small experiments to try at home.", sectionID: 3, memberIDs: ["backyard-sky", "tiny-garden", "science-sound", "bird-feeder", "cloud-journal"]),
    ]

    /// Mixed movie and episode playlist; includes one above-ceiling title so
    /// reviewers can see per-item filtering inside a playlist.
    private static let playlists = [
        Grouping(id: "playlist-saturday-morning", title: "Saturday Morning", summary: "A mixed family playlist.", sectionID: 0, memberIDs: ["space-camp-season-1-e-1", "moonbound", "kitchen-lab-season-1-e-2", "summit-signal", "tiny-garden"]),
    ]

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
            // Plex browse defaults to title order; the A-Z jump index assumes it.
            let records = recordsForSection(sectionID).sorted { sortTitle($0) < sortTitle($1) }
            return pagedContainer(records.map(itemJSON), request: request, query: query)
        case (_, let value) where value.hasPrefix("/library/sections/") && value.hasSuffix("/collections"):
            let sectionID = value.split(separator: "/").dropFirst(2).first.flatMap { Int($0) } ?? 0
            return itemContainer(collections.filter { $0.sectionID == sectionID }.map(collectionJSON))
        case (_, let value) where value.hasPrefix("/library/sections/") && value.hasSuffix("/firstCharacter"):
            let sectionID = value.split(separator: "/").dropFirst(2).first.flatMap { Int($0) } ?? 0
            return firstCharacterResponse(for: recordsForSection(sectionID))
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
        case (_, let value) where value.hasPrefix("/library/collections/"):
            let parts = value.split(separator: "/").map(String.init)
            guard parts.count >= 3, let collection = collections.first(where: { $0.id == parts[2] }) else {
                return itemContainer([])
            }
            return parts.last == "children"
                ? itemContainer(collection.memberIDs.compactMap(memberJSON))
                : itemContainer([collectionJSON(collection)])
        case (_, "/playlists"):
            return itemContainer(playlists.map(playlistJSON))
        case (_, let value) where value.hasPrefix("/playlists/"):
            let parts = value.split(separator: "/").map(String.init)
            guard parts.count >= 2, let playlist = playlists.first(where: { $0.id == parts[1] }) else {
                return itemContainer([])
            }
            return parts.last == "items"
                ? itemContainer(playlist.memberIDs.compactMap(memberJSON))
                : itemContainer([playlistJSON(playlist)])
        case (_, "/photo/:/transcode"):
            let artworkPath = query.first(where: { $0.name == "url" })?.value ?? ""
            return artworkResponse(forPath: artworkPath)
        case (_, let value) where value.hasPrefix("/artwork/"):
            return artworkResponse(forPath: value)
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

    private static func collectionJSON(_ collection: Grouping) -> [String: Any] {
        [
            "ratingKey": collection.id,
            "key": "/library/collections/\(collection.id)/children",
            "guid": "plex://fixture/\(collection.id)",
            "librarySectionID": collection.sectionID,
            "type": "collection",
            "subtype": "movie",
            "title": collection.title,
            "summary": collection.summary,
            "thumb": "/artwork/poster/\(collection.id).png",
            "art": "/artwork/backdrop/\(collection.id).png",
            "childCount": collection.memberIDs.count,
        ]
    }

    private static func playlistJSON(_ playlist: Grouping) -> [String: Any] {
        [
            "ratingKey": playlist.id,
            "key": "/playlists/\(playlist.id)/items",
            "guid": "plex://fixture/\(playlist.id)",
            "type": "playlist",
            "playlistType": "video",
            "smart": false,
            "title": playlist.title,
            "summary": playlist.summary,
            "composite": "/artwork/backdrop/\(playlist.id).png",
            "leafCount": playlist.memberIDs.count,
            "duration": playlist.memberIDs.count * clipDurationMS,
        ]
    }

    /// Resolves a movie/show record or a synthetic episode identifier.
    private static func memberJSON(_ id: String) -> [String: Any]? {
        if let record = allRecords.first(where: { $0.id == id }) {
            return itemJSON(record)
        }
        if let episode = episodeIDParts(id) {
            return episodeJSON(showID: episode.showID, season: episode.season, episode: episode.episode)
        }
        return nil
    }

    private static func sortTitle(_ record: Record) -> String {
        record.title.hasPrefix("The ") ? String(record.title.dropFirst(4)) : record.title
    }

    private static func firstCharacterResponse(for records: [Record]) -> DemoFixtureResponse {
        let counts = Dictionary(grouping: records) { sortTitle($0).prefix(1).uppercased() }
        let directory = counts.keys.sorted().map { key in
            ["key": key, "title": key, "size": counts[key]?.count ?? 0] as [String: Any]
        }
        return json(["MediaContainer": ["size": directory.count, "Directory": directory]])
    }

    private static func artworkResponse(forPath rawPath: String) -> DemoFixtureResponse {
        let path = URLComponents(string: rawPath)?.path ?? rawPath
        let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let title = allRecords.first(where: { $0.id == id })?.title
        guard let data = DemoFixtureArtwork.imageData(forPath: path, title: title) else {
            return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "unknown demo artwork"]))
        }
        return DemoFixtureResponse(statusCode: 200, mimeType: "image/jpeg", data: data)
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
            "titleSort": sortTitle(record),
            "summary": record.summary,
            "thumb": "/artwork/poster/\(record.id).png",
            "art": "/artwork/backdrop/\(record.id).png",
            "year": record.year,
            "duration": clipDurationMS,
            "studio": "Plinx Fixture Studio",
            "tagline": "Curiosity starts close to home.",
            "audienceRating": 8.4,
            "rating": 8.1,
            "Genre": [["tag": "Family"], ["tag": "Adventure"]],
            "Role": [["id": 1, "tag": "Avery North"], ["id": 2, "tag": "Jordan Vale"]],
            "Media": [[
                "id": 1,
                "videoResolution": "720",
                "container": "mp4",
                "duration": clipDurationMS,
                "Part": [["id": 1, "key": "/video/\(record.id).mp4", "container": "mp4", "duration": clipDurationMS]],
            ]],
        ]
        if let rating = record.rating {
            item["contentRating"] = rating
        }
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
        var season: [String: Any] = [
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
            "childCount": 2,
        ]
        if let rating = show.rating {
            season["contentRating"] = rating
        }
        return season
    }

    private static func episodeJSON(showID: String, season: Int, episode: Int) -> [String: Any] {
        let show = shows.first(where: { $0.id == showID }) ?? shows[0]
        let id = "\(showID)-season-\(season)-e-\(episode)"
        var episodeItem: [String: Any] = [
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
            "duration": clipDurationMS,
            "thumb": "/artwork/still/\(id).png",
            "art": "/artwork/backdrop/\(showID).png",
            "Media": [[
                "id": 1,
                "videoResolution": "720",
                "container": "mp4",
                "duration": clipDurationMS,
                "Part": [["id": 1, "key": "/video/\(id).mp4", "container": "mp4", "duration": clipDurationMS]],
            ]],
        ]
        if let rating = show.rating {
            episodeItem["contentRating"] = rating
        }
        return episodeItem
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

    /// Honors Plex paging (`X-Plex-Container-Start`/`-Size` headers or query
    /// items) so paged tvOS browse views never receive duplicate pages.
    private static func pagedContainer(
        _ items: [[String: Any]],
        request: URLRequest,
        query: [URLQueryItem],
    ) -> DemoFixtureResponse {
        func value(_ name: String) -> Int? {
            request.value(forHTTPHeaderField: name).flatMap(Int.init)
                ?? query.first(where: { $0.name == name })?.value.flatMap(Int.init)
        }
        let start = min(max(value("X-Plex-Container-Start") ?? 0, 0), items.count)
        let size = max(value("X-Plex-Container-Size") ?? items.count, 0)
        let page = Array(items[start..<min(start + size, items.count)])
        return json(["MediaContainer": ["size": page.count, "offset": start, "totalSize": items.count, "Metadata": page]])
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
