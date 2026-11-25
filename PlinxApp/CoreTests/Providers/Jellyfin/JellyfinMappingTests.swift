import Foundation
@testable import Plinx
import Testing

@MainActor
struct JellyfinMappingTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    @Test func `maps movie`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie")
        let media = MediaItem(jellyfinItem: item, server: server)

        #expect(media.id == "movie-1")
        #expect(media.identity == MediaIdentity(server: server, itemID: "movie-1"))
        #expect(media.guid == "jellyfin://server-1/movie-1")
        #expect(media.type == .movie)
        #expect(media.year == 2021)
        #expect(media.releaseDate == ISO8601DateFormatter().date(from: "2021-06-18T00:00:00Z"))
        #expect(media.duration == 7200)
        #expect(media.genres == ["Drama", "Thriller"])
        #expect(media.studio == "Example Studio")
        #expect(media.tagline == "The tagline.")
        #expect(media.contentRating == "PG-13")
        #expect(media.ratings == [
            MediaRating(source: .jellyfinCommunity, value: 7.4),
            MediaRating(source: .jellyfinCritics, value: 88),
        ])
        #expect(media.thumbPath == "jellyfin-artwork://movie-1/Primary?tag=primary-tag")
        #expect(media.artPath == "jellyfin-artwork://movie-1/Backdrop?tag=backdrop-tag")
        #expect(media.viewOffset == 600)
        #expect(media.viewCount == 0)
        #expect(media.watchState == MediaWatchState(
            isPlayed: false,
            playCount: 0,
            resumePosition: 600,
            unplayedItemCount: nil,
            isFavorite: true,
        ))
        #expect(media.lastViewedAt == ISO8601DateFormatter().date(from: "2026-03-14T20:15:30Z"))
    }

    @Test func `maps episode`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-episode")
        let media = MediaItem(jellyfinItem: item, server: server)

        #expect(media.type == .episode)
        #expect(media.parentRatingKey == "season-1")
        #expect(media.grandparentRatingKey == "series-1")
        #expect(media.grandparentTitle == "Example Show")
        #expect(media.parentTitle == "Season 1")
        #expect(media.parentIndex == 1)
        #expect(media.index == 1)
        #expect(media.thumbPath == nil)
        #expect(media.artPath == nil)
        #expect(media.grandparentThumbPath == "jellyfin-artwork://series-1/Primary?tag=series-tag")
        #expect(media.parentThumbPath == "jellyfin-artwork://season-1/Primary?tag=season-tag")
        #expect(media.grandparentArtPath == "jellyfin-artwork://series-1/Backdrop?tag=series-backdrop-tag")
        #expect(media.viewOffset == nil)
        // Jellyfin can report Played with a PlayCount of 0; the mapping still counts one view.
        #expect(media.viewCount == 1)
        #expect(media.watchState.isPlayed)
    }

    @Test func `episode backdrop is never used as series artwork`() throws {
        let json = #"{"Id":"episode-1","Name":"Pilot","Type":"Episode","BackdropImageTags":["episode-backdrop-tag"]}"#
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
        let media = MediaItem(jellyfinItem: item, server: server)

        #expect(media.grandparentArtPath == nil)
        #expect(media.artPath == "jellyfin-artwork://episode-1/Backdrop?tag=episode-backdrop-tag")
    }

    @Test func `maps display items by kind`() throws {
        let result = try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: "jellyfin-items")
        let items = result.items.map { MediaDisplayItem(jellyfinItem: $0, server: server) }

        try #require(items.count == 4)

        guard case let .collection(collection) = items[0] else {
            Issue.record("Expected a collection, got \(String(describing: items[0]))")
            return
        }
        #expect(collection.childCount == 3)
        #expect(collection.thumbPath == "jellyfin-artwork://boxset-1/Primary?tag=boxset-tag")

        guard case let .playlist(playlist) = items[1] else {
            Issue.record("Expected a playlist, got \(String(describing: items[1]))")
            return
        }
        #expect(playlist.duration == 9_000_000)
        #expect(playlist.leafCount == 12)

        #expect(items[2] == nil)

        guard case let .playable(trailer) = items[3] else {
            Issue.record("Expected a playable item, got \(String(describing: items[3]))")
            return
        }
        #expect(trailer.type == .clip)
    }

    @Test(arguments: [
        ("tvshows", MediaKind.series),
        ("TvShows", .series),
        ("boxsets", .collection),
        ("playlists", .playlist),
        ("movies", .movie),
        ("homevideos", .movie),
    ])
    func `maps library type`(collectionType: String, expected: MediaKind) throws {
        let json = #"{"Id":"lib","Name":"Library","CollectionType":"\#(collectionType)"}"#
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))

        #expect(Library(jellyfinItem: item, server: server).type == expected)
    }

    @Test(arguments: [
        (
            #"{"Index":2,"Type":"Audio","DisplayTitle":"English - AAC","Title":"Main","Language":"eng","Codec":"aac"}"#,
            "English - AAC",
        ),
        (#"{"Index":2,"Type":"Audio","Title":"Main","Language":"eng","Codec":"aac"}"#, "Main"),
        (#"{"Index":2,"Type":"Audio","Language":"eng","Codec":"aac"}"#, "eng"),
        (#"{"Index":2,"Type":"Audio","Codec":"aac"}"#, "aac"),
        (#"{"Index":2,"Type":"Audio"}"#, ""),
    ])
    func `track display title falls back`(json: String, expected: String) throws {
        let stream = try JSONDecoder().decode(JellyfinMediaStream.self, from: Data(json.utf8))
        let track = MediaTrackMetadata(jellyfinStream: stream)

        #expect(track.displayTitle == expected)
        #expect(track.id == 2)
        #expect(track.sourceIndex == 2)
        #expect(!track.isDefault)
        #expect(!track.isForced)
    }

    @Test func `chapter artwork path round trips`() throws {
        let path = JellyfinArtworkPath.makeChapter(ownerID: "movie-1", index: 4, tag: "chapter-tag")
        let parsed = try #require(JellyfinArtworkPath.parse(path))

        #expect(parsed.ownerID == "movie-1")
        #expect(parsed.type == "Chapter")
        #expect(parsed.index == 4)
        #expect(parsed.tag == "chapter-tag")
    }

    @Test func `decodes theme songs`() throws {
        let themes = try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: "jellyfin-theme-songs")

        #expect(themes.items.map(\.id) == ["theme-1"])
    }

    @Test func `maps the first source's resolution`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie-versions")

        #expect(MediaItem(jellyfinItem: item, server: server).videoResolution == "1080p")
    }

    @Test func `a 4K film cropped to scope is 4K`() throws {
        let source = try JSONDecoder().decode(JellyfinMediaSource.self, from: Data("""
        { "Id": "s", "MediaStreams": [{ "Type": "Video", "Index": 0, "Width": 3840, "Height": 1600 }] }
        """.utf8))

        #expect(source.videoResolution == "4K")
    }

    @Test func `artwork path requires tag`() {
        #expect(JellyfinArtworkPath.make(ownerID: "movie-1", type: "Primary", tag: nil) == nil)
        #expect(JellyfinArtworkPath.parse("https://example.com/image") == nil)
    }

    // MARK: - Content rating

    @Test func `maps a custom rating stricter than the official one`() throws {
        let json = #"{"Id":"movie-2","Name":"Restricted","Type":"Movie","OfficialRating":"PG","CustomRating":"R"}"#
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))

        #expect(item.officialRating == "PG")
        #expect(item.customRating == "R")
        #expect(MediaItem(jellyfinItem: item, server: server).contentRating == "R")
    }

    @Test func `judges the stricter of the official and custom ratings`() {
        let cases: [(official: String?, custom: String?, judged: String?)] = [
            ("PG-13", nil, "PG-13"),
            ("PG-13", "  ", "PG-13"),
            (nil, "R", "R"),
            ("", "TV-14", "TV-14"),
            (nil, nil, nil),
            // Of two recognized ratings, the more severe one, on either scale.
            ("PG", "R", "R"),
            ("TV-Y7", "TV-14", "TV-14"),
            ("TV-PG", "PG-13", "PG-13"),
            // A custom rating never loosens a recognized official one.
            ("R", "PG", "R"),
            ("PG-13", "TV-Y7", "PG-13"),
            ("PG", "PG", "PG"),
            // Adult-only wins from either side.
            ("G", "NC-17", "NC-17"),
            ("NC-17", "G", "NC-17"),
            ("PG", "X", "X"),
            // A rating Plinx cannot read never replaces one it can.
            ("PG", "15", "PG"),
            ("Not Rated", "TV-MA", "TV-MA"),
            // Neither readable: the custom one, as on Jellyfin. Both are unrated.
            ("Not Rated", "Approved", "Approved"),
        ]
        for (official, custom, judged) in cases {
            #expect(
                JellyfinContentRating.resolve(official: official, custom: custom) == judged,
                "official \(official ?? "nil"), custom \(custom ?? "nil")"
            )
        }
    }

    @Test func `every item field list asks for the custom rating`() {
        let lists = [
            JellyfinCatalogService.cardFields,
            JellyfinCatalogService.detailFields,
            JellyfinCatalogService.playbackFields,
            JellyfinCatalogService.featuredFields,
            JellyfinCatalogService.queueFields,
        ]
        for fields in lists {
            #expect(fields.split(separator: ",").contains("CustomRating"), "\(fields)")
        }
    }
}
