import PlinxCore
import XCTest
@testable import Plinx

// ─────────────────────────────────────────────────────────────────────────────
// SafeMediaServicesTests — conformance test for the content-safety boundary
// ─────────────────────────────────────────────────────────────────────────────
//
// A fake provider returns, from every content method, one allowed title next
// to an over-ceiling, an unrated and an adult-only one. Every test goes through
// a real `MediaServices`, whose initializer applies `SafeMediaServices`.
//
// How the guard works:
//   1. `test_reviewedRequirementsMatchTheProviderProtocols` parses the provider
//      protocol declarations from source and fails when a requirement (or a
//      whole protocol) is missing from `SafeMediaServices.reviewedRequirements`,
//      or when that table lists one that no longer exists.
//   2. `test_everyFilteredRequirementHasAContentProbe` fails when a `.filtered`
//      requirement has no entry in `contentProbes` below.
//   3. `test_blockedTitlesNeverLeaveTheBoundary` runs every probe and fails if
//      a blocked title comes out, or if a probe returns no allowed title (so a
//      probe cannot pass by returning nothing).
//
// Adding a provider method therefore means: implement it in the wrapper, list
// it in `reviewedRequirements`, and, if it returns titles, add a probe here.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SafeMediaServicesTests: XCTestCase {
    // MARK: - Requirement table vs. provider protocols

    func test_reviewedRequirementsMatchTheProviderProtocols() throws {
        var parsed: [String: Set<String>] = [:]
        for file in ProviderProtocolSources.allProtocolFiles {
            let source = try ProviderProtocolSources.read(file)
            for name in ProtocolRequirementParser.protocolNames(in: source) {
                parsed[name] = ProtocolRequirementParser.requirements(of: name, in: source)
            }
        }
        for (file, name) in ProviderProtocolSources.namedProtocols {
            let source = try ProviderProtocolSources.read(file)
            parsed[name] = ProtocolRequirementParser.requirements(of: name, in: source)
        }

        let reviewed = SafeMediaServices.reviewedRequirements.mapValues { Set($0.keys) }
        XCTAssertEqual(
            Set(parsed.keys),
            Set(reviewed.keys),
            "Every provider protocol must be listed in SafeMediaServices.reviewedRequirements",
        )
        for (name, requirements) in parsed {
            let listed = reviewed[name] ?? []
            XCTAssertFalse(requirements.isEmpty, "Parsed no requirement from \(name)")
            XCTAssertEqual(
                requirements.subtracting(listed).sorted(),
                [],
                "\(name) requirements missing from SafeMediaServices.reviewedRequirements",
            )
            XCTAssertEqual(
                listed.subtracting(requirements).sorted(),
                [],
                "\(name) requirements listed in SafeMediaServices.reviewedRequirements no longer exist",
            )
        }
    }

    func test_parserReadsSelectorsWithLabels() {
        let source = """
        @MainActor
        protocol Sample: AnyObject {
            /// A comment mentioning func ignored(x:)
            var flag: Bool { get }
            func load(
                id: String,
                _ value: Int,
                handler: @escaping (Int, String) -> Void,
                map: [String: Set<Int>],
            ) async throws -> [String]
            func plain() async
        }
        protocol Other {}
        """
        XCTAssertEqual(ProtocolRequirementParser.protocolNames(in: source), ["Sample", "Other"])
        XCTAssertEqual(
            ProtocolRequirementParser.requirements(of: "Sample", in: source),
            ["flag", "load(id:_:handler:map:)", "plain()"],
        )
    }

    func test_everyFilteredRequirementHasAContentProbe() {
        let filtered = SafeMediaServices.reviewedRequirements.flatMap { name, requirements in
            requirements.filter { $0.value == .filtered }.map { "\(name).\($0.key)" }
        }
        let probes = Set(contentProbes.keys)
        XCTAssertEqual(Set(filtered).subtracting(probes).sorted(), [], "Filtered requirements without a probe")
        XCTAssertEqual(probes.subtracting(filtered).sorted(), [], "Probes for requirements not marked filtered")
    }

    // MARK: - Content

    func test_blockedTitlesNeverLeaveTheBoundary() async throws {
        for (requirement, probe) in contentProbes.sorted(by: { $0.key < $1.key }) {
            let fixture = Fixture()
            let ids = try await probe(fixture)
            let leaked = ids.filter(FakeTitles.isBlocked)
            XCTAssertEqual(leaked, [], "\(requirement) let blocked titles through")
            XCTAssertTrue(ids.contains(where: FakeTitles.isAllowed), "\(requirement) returned no allowed title")
        }
    }

    func test_pagedListingsStayConsistentAfterFiltering() async throws {
        let fixture = Fixture()
        let library = fixture.library
        let expected = fixture.provider.listing.filter { FakeTitles.isAllowed($0.id) }.map(\.id)
        let hub = FakeTitles.hub(id: "listing", items: [])

        let listings: [(String, (Int, Int) async throws -> PageResult)] = [
            ("hub items", { start, limit in
                let page = try await fixture.plex.home.items(in: hub, startIndex: start, limit: limit)
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            }),
            ("library items", { start, limit in
                let page = try await fixture.plex.library.items(
                    in: library,
                    parentID: nil,
                    startIndex: start,
                    limit: limit,
                )
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            }),
            ("collection page, no server total", { start, limit in
                let service = try XCTUnwrap(fixture.plex.library as? any PlexAdvancedLibraryService)
                let page = try await service.collectionPage(sectionID: 1, startIndex: start, limit: limit)
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            }),
            ("Jellyfin browse", { start, limit in
                let service = try XCTUnwrap(fixture.jellyfin.library as? any AdvancedLibraryBrowseService)
                let page = try await service.browseItems(
                    in: library,
                    parentID: nil,
                    query: LibraryBrowseQuery(),
                    startIndex: start,
                    limit: limit,
                )
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            }),
        ]

        for (name, load) in listings {
            for limit in [4, 7, 40] {
                let ids = try await pageThrough(limit: limit, name: name, load)
                XCTAssertEqual(ids, expected, "\(name) with pages of \(limit)")
            }
        }

        // Plex advanced browse keeps folders, which are containers.
        let advanced = try XCTUnwrap(fixture.plex.library as? any PlexAdvancedLibraryService)
        let browsed = try await pageThrough(limit: 6, name: "advanced browse") { start, limit in
            let page = try await advanced.advancedBrowse(
                path: "/library/sections/1/all",
                queryItems: [URLQueryItem(name: "includeMeta", value: start == 0 ? "1" : nil)],
                startIndex: start,
                limit: limit,
            )
            return PageResult(
                ids: page.items.map(\.id),
                startIndex: start,
                total: page.totalCount,
            )
        }
        XCTAssertEqual(browsed, ["folder"] + expected)
    }

    func test_queuesDropBlockedTitlesAndRefuseABlockedStart() async throws {
        let fixture = Fixture()
        let queue = try await fixture.plex.playback.queue(startingWith: fixture.provider.allowed, shuffle: false)
        XCTAssertEqual(queue.items.map(\.media.id), ["allowed"])
        XCTAssertEqual(queue.currentIndex, 0)

        for blocked in fixture.provider.blockedTitles {
            await assertThrows(.blocked) {
                _ = try await fixture.plex.playback.queue(startingWith: blocked.id, kind: .movie, shuffle: false)
            }
        }
    }

    func test_blockedDownloadIsCancelledOnTheServer() async throws {
        let fixture = Fixture()
        await assertThrows(.blocked) {
            _ = try await fixture.plex.downloads.prepareDownload(
                itemID: "over-ceiling",
                quality: .original,
                tracks: .serverDefault,
                version: .automatic,
            )
        }
        XCTAssertTrue(fixture.provider.calls.contains("cancelDownloadPreparation:session-over-ceiling"))
    }

    func test_policyChangeAppliesToTheNextRequestAndRevisesTheHome() async throws {
        let fixture = Fixture()
        let revision = fixture.plex.homeContentRevision

        fixture.gate.policy = .ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: true)

        XCTAssertEqual(fixture.gate.revision, 1)
        XCTAssertGreaterThan(fixture.plex.homeContentRevision, revision)
        let results = try await fixture.plex.search.search(query: "anything", kinds: [])
        // Adult-only ratings stay blocked whatever the ceiling.
        XCTAssertEqual(results.map(\.id), ["allowed", "over-ceiling", "unrated"])
    }

    func test_unchangedPolicyKeepsTheRevision() {
        let gate = ContentSafetyGate(policy: .ratingOnly())
        gate.policy = .ratingOnly()
        XCTAssertEqual(gate.revision, 0)
    }

    func test_containersAreListedAndTheirEntriesFiltered() async throws {
        let fixture = Fixture()
        let collection = MediaDisplayItem.collection(
            CollectionMediaItem(
                id: "collection",
                key: "collection",
                guid: "plex://collection",
                type: .collection,
                title: "Collection",
                summary: nil,
                thumbPath: nil,
                childCount: 4,
                minYear: nil,
                maxYear: nil,
                server: FakeTitles.server,
            ),
        )
        XCTAssertTrue(fixture.gate.isAllowed(collection))
        let entries = try await fixture.plex.detail.collectionItems(id: "collection")
        XCTAssertEqual(entries.map(\.id), ["allowed"])
    }

    // MARK: - Parent-only and disabled abilities

    func test_parentOnlyAbilitiesNeedTheGateUnlocked() async throws {
        let fixture = Fixture()
        let services = fixture.plex
        let playlist = FakeTitles.playlist

        XCTAssertEqual(services.authorization, .denied)
        XCTAssertFalse(services.detail.supportsRemoteSubtitleSearch)
        XCTAssertFalse(services.detail.supportsAdvancedSubtitleSearch)
        XCTAssertFalse(services.detail.supportsWatchlist)
        let watchlistedLocked = try await services.detail.isWatchlisted(fixture.provider.allowed)
        XCTAssertFalse(watchlistedLocked)
        await assertThrows(.parentApprovalRequired) {
            try await services.detail.setWatchlisted(true, media: fixture.provider.allowed)
        }
        let canEditLocked = try await services.playlists.canEdit(playlist)
        XCTAssertFalse(canEditLocked)
        let editableLocked = try await services.playlists.editablePlaylists()
        XCTAssertTrue(editableLocked.isEmpty)
        await assertThrows(.parentApprovalRequired) {
            try await services.playlists.add(itemID: "allowed", toPlaylist: "playlist")
        }
        await assertThrows(.parentApprovalRequired) {
            try await services.playlists.delete(playlistID: "playlist")
        }
        await assertThrows(.parentApprovalRequired) {
            _ = try await services.detail.searchSubtitles(
                itemID: "allowed",
                language: "en",
                hearingImpaired: false,
                forced: false,
                title: nil,
            )
        }
        await assertThrows(.parentApprovalRequired) {
            try await services.management.refreshMetadata(itemID: "allowed")
        }
        await assertThrows(.parentApprovalRequired) {
            try await services.management.delete(fixture.provider.allowed)
        }
        XCTAssertTrue(services.management.artworkKinds(for: fixture.provider.allowed).isEmpty)
        XCTAssertEqual(fixture.provider.calls, [], "Nothing reached the provider while locked")

        fixture.gate.isParentUnlocked = true

        XCTAssertEqual(services.authorization, .plex(isAdministrator: true, allowsMediaDeletion: true))
        XCTAssertTrue(services.detail.supportsRemoteSubtitleSearch)
        XCTAssertTrue(services.detail.supportsWatchlist)
        let canEditUnlocked = try await services.playlists.canEdit(playlist)
        XCTAssertTrue(canEditUnlocked)
        try await services.playlists.add(itemID: "allowed", toPlaylist: "playlist")
        _ = try await services.detail.searchSubtitles(
            itemID: "allowed",
            language: "en",
            hearingImpaired: false,
            forced: false,
            title: nil,
        )
        try await services.detail.setWatchlisted(true, media: fixture.provider.allowed)
        try await services.management.refreshMetadata(itemID: "allowed")
        XCTAssertEqual(fixture.provider.calls, ["canEdit", "add", "searchSubtitles", "setWatchlisted"])
    }

    func test_liveTVAndExternalPlayersAreOff() async throws {
        let fixture = Fixture()
        let services = fixture.plex

        let isAvailable = try await services.liveTV.isAvailable()
        XCTAssertFalse(isAvailable)
        XCTAssertNil(services.liveTV.dvr)
        XCTAssertFalse(services.liveTV.supportsServerCaptureBuffer)
        let channels = try await services.liveTV.channels()
        XCTAssertTrue(channels.isEmpty)
        let onNow = try await services.liveTV.onNow()
        XCTAssertTrue(onNow.isEmpty)
        await assertThrows(.unavailable) {
            _ = try await services.playback.externalPlaybackTarget(
                for: fixture.provider.allowed,
                version: .automatic,
            )
        }
        let advanced = try XCTUnwrap(services.library as? any PlexAdvancedLibraryService)
        let characters = try await advanced.sectionCharacters(path: "/library/sections/1/firstCharacter", queryItems: [])
        XCTAssertTrue(characters.isEmpty, "Unfiltered letter counts would misplace the filtered listing")
        XCTAssertEqual(fixture.provider.calls, [])
    }

    func test_wrappedServicesKeepTheOptionalProviderAbilities() {
        let fixture = Fixture()
        XCTAssertTrue(fixture.plex.library is SafePlexLibraryService)
        XCTAssertNotNil(fixture.plex.library as? any PlexAdvancedLibraryService)
        XCTAssertNil(fixture.plex.library as? any AdvancedLibraryBrowseService)
        XCTAssertTrue(fixture.jellyfin.library is SafeBrowseLibraryService)
        XCTAssertNotNil(fixture.jellyfin.library as? any AdvancedLibraryBrowseService)
        XCTAssertNotNil(fixture.plex.playback as? any MediaTrackSelectionMemoryService)
        XCTAssertTrue(fixture.plex.home is SafeHomeService)
        XCTAssertTrue(fixture.plex.detail is SafeDetailService)
        XCTAssertTrue(fixture.plex.liveTV is DisabledLiveTVService)
    }

    // MARK: - Content probes

    private typealias Probe = @MainActor (Fixture) async throws -> [String]

    /// One probe per `.filtered` requirement, keyed `Protocol.selector`. Each returns the ids of every title that left
    /// the boundary, and checks that looking up a blocked subject is refused.
    private var contentProbes: [String: Probe] {
        var probes: [String: Probe] = [:]
        // Home
        probes["MediaHomeService.loadHome(hiddenLibraryIDs:includesPlaylists:shownRowIDs:mergesNextUp:)"] = { fixture in
            let content = try await fixture.plex.home.loadHome(
                hiddenLibraryIDs: [],
                includesPlaylists: true,
                shownRowIDs: [],
                mergesNextUp: false,
            )
            XCTAssertEqual(content.rows.map(\.id), ["mixed"], "A row emptied by filtering is dropped")
            return FakeTitles.ids(in: content.rows)
        }
        probes["MediaHomeService.loadWatchingRows(hiddenLibraryIDs:mergesNextUp:)"] = { fixture in
            let rows = try await fixture.plex.home.loadWatchingRows(hiddenLibraryIDs: [], mergesNextUp: true)
            XCTAssertEqual(rows.map(\.id), ["mixed"])
            return FakeTitles.ids(in: rows)
        }
        probes["MediaHomeService.homeRowCatalog(hiddenLibraryIDs:)"] = { fixture in
            let rows = try await fixture.plex.home.homeRowCatalog(hiddenLibraryIDs: [])
            XCTAssertEqual(rows.map(\.id), ["mixed", "blocked-only"], "The settings catalog keeps every row")
            return FakeTitles.ids(in: rows)
        }
        probes["MediaHomeService.loadFeaturedCandidates(hiddenLibraryIDs:)"] = { fixture in
            try await fixture.plex.home.loadFeaturedCandidates(hiddenLibraryIDs: []).map(\.item.id)
        }
        probes["MediaHomeService.items(in:startIndex:limit:)"] = { fixture in
            let page = try await fixture.plex.home.items(
                in: FakeTitles.hub(id: "mixed", items: []),
                startIndex: 0,
                limit: 500,
            )
            return page.items.map(\.id)
        }
        // Library
        probes["MediaLibraryService.preview(for:)"] = { fixture in
            let preview = try await fixture.plex.library.preview(for: fixture.library)
            XCTAssertNil(preview?.itemCount, "The unfiltered library size is not shown")
            return (preview?.artworks ?? []).map(FakeTitles.id(of:))
        }
        probes["MediaLibraryService.recommended(in:mergesNextUp:)"] = { fixture in
            let hubs = try await fixture.plex.library.recommended(in: fixture.library, mergesNextUp: false)
            XCTAssertEqual(hubs.map(\.id), ["mixed"])
            return hubs.flatMap { $0.items.map(\.id) }
        }
        probes["MediaLibraryService.items(in:parentID:startIndex:limit:)"] = { fixture in
            try await fixture.plex.library.items(
                in: fixture.library,
                parentID: nil,
                startIndex: 0,
                limit: 500,
            ).items.map(\.id)
        }
        probes["PlexAdvancedLibraryService.advancedBrowse(path:queryItems:startIndex:limit:)"] = { fixture in
            let service = try XCTUnwrap(fixture.plex.library as? any PlexAdvancedLibraryService)
            return try await service.advancedBrowse(
                path: "/library/sections/1/all",
                queryItems: [],
                startIndex: 0,
                limit: 500,
            ).items.map(\.id)
        }
        probes["PlexAdvancedLibraryService.collectionPage(sectionID:startIndex:limit:)"] = { fixture in
            let service = try XCTUnwrap(fixture.plex.library as? any PlexAdvancedLibraryService)
            return try await service.collectionPage(sectionID: 1, startIndex: 0, limit: 500).items.map(\.id)
        }
        probes["AdvancedLibraryBrowseService.browseItems(in:parentID:query:startIndex:limit:)"] = { fixture in
            let service = try XCTUnwrap(fixture.jellyfin.library as? any AdvancedLibraryBrowseService)
            return try await service.browseItems(
                in: fixture.library,
                parentID: nil,
                query: LibraryBrowseQuery(),
                startIndex: 0,
                limit: 500,
            ).items.map(\.id)
        }
        // Search
        probes["MediaSearchService.search(query:kinds:)"] = { fixture in
            try await fixture.plex.search.search(query: "anything", kinds: [.movie]).map(\.id)
        }
        // Detail
        probes["MediaDetailService.mediaItem(id:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) { _ = try await fixture.plex.detail.mediaItem(id: blocked.id) }
            }
            return try await [fixture.plex.detail.mediaItem(id: "allowed").id]
        }
        probes["MediaDetailService.details(for:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) { _ = try await fixture.plex.detail.details(for: blocked) }
            }
            let content = try await fixture.plex.detail.details(for: fixture.provider.allowed)
            XCTAssertNil(content.parentSeries)
            XCTAssertNil(content.onDeck)
            XCTAssertEqual(content.relatedHubs.map(\.id), ["mixed"])
            return [content.media.id]
                + content.seasons.map(\.id)
                + content.episodes.map(\.id)
                + content.relatedHubs.flatMap { $0.items.map(\.id) }
        }
        probes["MediaDetailService.fileInfo(for:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) { _ = try await fixture.plex.detail.fileInfo(for: blocked) }
            }
            _ = try await fixture.plex.detail.fileInfo(for: fixture.provider.allowed)
            return ["allowed"]
        }
        probes["MediaDetailService.fetchExtras(for:)"] = { fixture in
            try await fixture.plex.detail.fetchExtras(for: fixture.provider.allowed).map(\.id)
        }
        probes["MediaDetailService.otherEditions(of:)"] = { fixture in
            try await fixture.plex.detail.otherEditions(of: fixture.provider.allowed).map(\.id)
        }
        probes["MediaDetailService.seasons(for:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) { _ = try await fixture.plex.detail.seasons(for: blocked) }
            }
            return try await fixture.plex.detail.seasons(for: fixture.provider.allowed).map(\.id)
        }
        probes["MediaDetailService.episodes(for:seriesID:)"] = { fixture in
            try await fixture.plex.detail.episodes(for: fixture.provider.allowed, seriesID: nil).map(\.id)
        }
        probes["MediaDetailService.allEpisodes(for:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) { _ = try await fixture.plex.detail.allEpisodes(for: blocked) }
            }
            return try await fixture.plex.detail.allEpisodes(for: fixture.provider.allowed).map(\.id)
        }
        probes["MediaDetailService.collectionItems(id:)"] = { fixture in
            try await fixture.plex.detail.collectionItems(id: "collection").map(\.id)
        }
        probes["MediaDetailService.personMedia(id:)"] = { fixture in
            try await fixture.plex.detail.personMedia(id: "person").map(\.id)
        }
        // Favorites and playlists
        probes["MediaFavoritesService.favorites()"] = { fixture in
            try await fixture.plex.favorites.favorites().map(\.id)
        }
        probes["MediaPlaylistService.playlistEntries(id:)"] = { fixture in
            try await fixture.plex.playlists.playlistEntries(id: "playlist").map(\.media.id)
        }
        // Playback
        probes["MediaPlaybackService.queue(startingWith:kind:shuffle:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) {
                    _ = try await fixture.plex.playback.queue(startingWith: blocked.id, kind: .movie, shuffle: false)
                }
            }
            let queue = try await fixture.plex.playback.queue(startingWith: "allowed", kind: .movie, shuffle: true)
            XCTAssertEqual(queue.items[queue.currentIndex].media.id, "allowed")
            return queue.items.map(\.media.id)
        }
        probes["MediaPlaybackService.queue(startingWith:shuffle:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) {
                    _ = try await fixture.plex.playback.queue(startingWith: blocked, shuffle: false)
                }
            }
            let queue = try await fixture.plex.playback.queue(startingWith: fixture.provider.allowed, shuffle: false)
            XCTAssertEqual(queue.items[queue.currentIndex].media.id, "allowed")
            return queue.items.map(\.media.id)
        }
        probes["MediaPlaybackService.queue(playlistID:startingWith:)"] = { fixture in
            let entries = FakeTitles.entries(fixture.provider.titles)
            for entry in entries where FakeTitles.isBlocked(entry.media.id) {
                await assertThrows(.blocked) {
                    _ = try await fixture.plex.playback.queue(playlistID: "playlist", startingWith: entry)
                }
            }
            let allowedEntry = try XCTUnwrap(entries.first { $0.media.id == "allowed" })
            let queue = try await fixture.plex.playback.queue(playlistID: "playlist", startingWith: allowedEntry)
            return queue.items.map(\.media.id)
        }
        probes["MediaPlaybackService.prepare(media:resume:quality:trackPreference:version:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) {
                    _ = try await fixture.plex.playback.prepare(
                        media: blocked,
                        resume: false,
                        quality: .original,
                        trackPreference: nil,
                        version: .automatic,
                    )
                }
            }
            XCTAssertEqual(fixture.provider.calls, [], "No stream was prepared for a blocked title")
            do {
                _ = try await fixture.plex.playback.prepare(
                    media: fixture.provider.allowed,
                    resume: false,
                    quality: .original,
                    trackPreference: nil,
                    version: .automatic,
                )
            } catch FakeProviderError.reachedProvider {
                // The fake cannot build a plan; reaching it is what this probe checks.
            }
            XCTAssertEqual(fixture.provider.calls, ["prepare:allowed"])
            return ["allowed"]
        }
        // Downloads
        probes["MediaDownloadService.prepareDownload(itemID:quality:tracks:version:)"] = { fixture in
            for blocked in fixture.provider.blockedTitles {
                await assertThrows(.blocked) {
                    _ = try await fixture.plex.downloads.prepareDownload(
                        itemID: blocked.id,
                        quality: .original,
                        tracks: .serverDefault,
                        version: .automatic,
                    )
                }
            }
            let preparation = try await fixture.plex.downloads.prepareDownload(
                itemID: "allowed",
                quality: .original,
                tracks: .serverDefault,
                version: .automatic,
            )
            return [preparation.media.id]
        }
        probes["MediaDownloadService.downloadableItems(itemID:kind:)"] = { fixture in
            try await fixture.plex.downloads.downloadableItems(itemID: "allowed", kind: .series).map(\.id)
        }
        return probes
    }

    // MARK: - Helpers

    private struct PageResult {
        let ids: [String]
        let startIndex: Int
        let total: Int?
    }

    /// Pages through a listing the way the browse screens do and checks the paging contract: each page starts where it
    /// was asked to, no page reports more titles than the listing ends up holding, and the last one reports the exact
    /// count.
    private func pageThrough(
        limit: Int,
        name: String,
        _ load: (Int, Int) async throws -> PageResult,
    ) async throws -> [String] {
        var ids: [String] = []
        var totals: [Int] = []
        var start = 0
        for _ in 0 ..< 200 {
            let page = try await load(start, limit)
            XCTAssertEqual(page.startIndex, start, "\(name) page start")
            XCTAssertLessThanOrEqual(page.ids.count, limit, "\(name) page size")
            ids += page.ids
            start += page.ids.count
            if let total = page.total {
                totals.append(total)
            }
            if page.ids.isEmpty || page.total.map({ start >= $0 }) == true {
                break
            }
        }
        XCTAssertEqual(totals.last, ids.count, "\(name) last page reports the exact filtered count")
        XCTAssertTrue(totals.allSatisfy { $0 <= ids.count }, "\(name) never reports more titles than exist: \(totals)")
        XCTAssertEqual(Set(ids).count, ids.count, "\(name) repeated a title")
        return ids
    }
}

/// `XCTAssertThrowsError` takes no async closure.
@MainActor
private func assertThrows(
    _ expected: ContentSafetyError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void,
) async {
    do {
        try await body()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? ContentSafetyError, expected, "\(error)", file: file, line: line)
    }
}

// MARK: - Fixture

@MainActor
private struct Fixture {
    let gate = ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg, maxTV: .tvY7))
    let provider = FakeProvider()
    let plex: MediaServices
    let jellyfin: MediaServices
    let library = Library(id: "1", title: "Movies", type: .movie, sectionId: 1, server: FakeTitles.server)

    init() {
        plex = Self.services(provider: provider, library: FakePlexLibrary(provider: provider), gate: gate)
        jellyfin = Self.services(provider: provider, library: FakeBrowseLibrary(provider: provider), gate: gate)
    }

    private static func services(
        provider: FakeProvider,
        library: any MediaLibraryService,
        gate: ContentSafetyGate,
    ) -> MediaServices {
        MediaServices(
            provider: .plex,
            identity: FakeTitles.server,
            serverName: "Fake",
            capabilities: .plex,
            home: provider,
            library: library,
            search: provider,
            artwork: provider,
            detail: provider,
            favorites: provider,
            playlists: provider,
            playback: provider,
            liveTV: provider,
            downloads: provider,
            authorization: provider,
            contentGate: gate,
        )
    }
}

private enum FakeTitles {
    static let server = ServerIdentity(provider: .plex, id: "fake-server")

    static func isBlocked(_ id: String) -> Bool {
        id.contains("over-ceiling") || id.contains("unrated") || id.contains("adult")
    }

    static func isAllowed(_ id: String) -> Bool {
        !isBlocked(id)
    }

    static func media(_ id: String, rating: String?, type: MediaKind = .movie) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: "plex://\(id)",
            summary: nil,
            title: id,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
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

    static func hub(id: String, items: [MediaDisplayItem]) -> Hub {
        Hub(
            id: id,
            key: "/hubs/\(id)",
            hubKey: nil,
            title: id,
            size: items.count,
            more: false,
            items: items,
            server: server,
        )
    }

    static func row(id: String, items: [MediaItem], copies: [MediaIdentity: [MediaItem]] = [:]) -> HomeRow {
        HomeRow(
            id: id,
            kind: .hub,
            style: .portrait,
            hub: hub(id: id, items: items.map(MediaDisplayItem.playable)),
            copies: copies,
        )
    }

    static func ids(in rows: [HomeRow]) -> [String] {
        rows.flatMap { row in
            row.items.map(\.id) + row.copies.values.flatMap { $0.map(\.id) }
        }
    }

    static func entries(_ titles: [MediaItem]) -> [PlaylistEntry] {
        PlaylistEntry.entries(titles.map { (entryID: $0.id, media: MediaDisplayItem.playable($0)) })
    }

    static func artwork(for id: String) -> ArtworkResource {
        .data(Data(id.utf8))
    }

    static func id(of artwork: ArtworkResource) -> String {
        switch artwork {
        case let .data(data):
            String(decoding: data, as: UTF8.self)
        case let .url(url):
            url.lastPathComponent
        }
    }

    static let playlist = PlaylistMediaItem(
        id: "playlist",
        key: "playlist",
        guid: "plex://playlist",
        type: .playlist,
        title: "Playlist",
        summary: nil,
        compositePath: nil,
        duration: nil,
        leafCount: 4,
        playlistType: "video",
        server: server,
    )
}

private enum FakeProviderError: Error {
    case reachedProvider
    case notFound
}

// MARK: - Fake provider

/// Returns the allowed title next to blocked ones from every content method, and records every parent-only or
/// disabled call that reaches it.
@MainActor
private final class FakeProvider: MediaHomeService, MediaSearchService, MediaArtworkService, MediaDetailService,
    MediaFavoritesService, MediaPlaylistService, MediaPlaybackService, MediaTrackSelectionMemoryService,
    MediaLiveTVService, MediaDownloadService, MediaAuthorizationService
{
    let allowed = FakeTitles.media("allowed", rating: "PG")
    let overCeiling = FakeTitles.media("over-ceiling", rating: "R")
    let unrated = FakeTitles.media("unrated", rating: nil)
    let adultOnly = FakeTitles.media("adult-only", rating: "NC-17")
    /// A long server listing, so filtered paging needs several server pages.
    let listing: [MediaItem] = (0 ..< 150).map { index in
        switch index % 3 {
        case 0: FakeTitles.media("page\(index)-allowed", rating: "TV-Y7", type: .series)
        case 1: FakeTitles.media("page\(index)-over-ceiling", rating: "TV-14", type: .series)
        default: FakeTitles.media("page\(index)-unrated", rating: "Not Rated", type: .series)
        }
    }

    private(set) var calls: [String] = []

    var titles: [MediaItem] {
        [allowed, overCeiling, unrated, adultOnly]
    }

    var blockedTitles: [MediaItem] {
        [overCeiling, unrated, adultOnly]
    }

    var displayTitles: [MediaDisplayItem] {
        titles.map(MediaDisplayItem.playable)
    }

    func listingPage(start: Int, limit: Int) -> [MediaItem] {
        guard start < listing.count else { return [] }
        return Array(listing[start ..< min(start + limit, listing.count)])
    }

    private var rows: [HomeRow] {
        [
            FakeTitles.row(
                id: "mixed",
                items: titles,
                copies: [
                    allowed.identity: [allowed, overCeiling],
                    overCeiling.identity: [overCeiling],
                ],
            ),
            FakeTitles.row(id: "blocked-only", items: blockedTitles),
        ]
    }

    private var hubs: [Hub] {
        rows.map(\.hub)
    }

    private func title(_ id: String) throws -> MediaItem {
        guard let title = titles.first(where: { $0.id == id }) else { throw FakeProviderError.notFound }
        return title
    }

    // MediaHomeService

    func loadHome(
        hiddenLibraryIDs _: Set<String>,
        includesPlaylists _: Bool,
        shownRowIDs _: Set<String>,
        mergesNextUp _: Bool,
    ) async throws -> HomeContent {
        HomeContent(rows: rows)
    }

    func loadWatchingRows(hiddenLibraryIDs _: Set<String>, mergesNextUp _: Bool) async throws -> [HomeRow] {
        rows
    }

    func homeRowCatalog(hiddenLibraryIDs _: Set<String>) async throws -> [HomeRow] {
        rows
    }

    func loadFeaturedCandidates(hiddenLibraryIDs _: Set<String>) async throws -> [FeaturedCandidate] {
        titles.map { FeaturedCandidate(item: $0, reason: .recentlyAdded) }
    }

    func items(in hub: Hub, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        if hub.id == "listing" {
            return MediaPage(
                items: listingPage(start: startIndex, limit: limit).map(MediaDisplayItem.playable),
                startIndex: startIndex,
                totalCount: listing.count,
            )
        }
        let items = startIndex == 0 ? displayTitles : []
        return MediaPage(items: items, startIndex: startIndex, totalCount: displayTitles.count)
    }

    // MediaSearchService

    func search(query _: String, kinds _: Set<MediaKind>) async throws -> [MediaDisplayItem] {
        displayTitles
    }

    // MediaArtworkService

    func artworkURL(path _: String?, width _: Int?, height _: Int?) -> URL? {
        nil
    }

    func artwork(
        for media: MediaDisplayItem,
        kind _: MediaImageViewModel.ArtworkKind,
        width _: Int?,
        height _: Int?,
    ) async throws -> ArtworkResource? {
        FakeTitles.artwork(for: media.id)
    }

    func artwork(path _: String?, width _: Int?, height _: Int?) async throws -> ArtworkResource? {
        nil
    }

    // MediaDetailService

    var supportsWatchlist: Bool {
        true
    }

    var supportsRemoteSubtitleSearch: Bool {
        true
    }

    var supportsAdvancedSubtitleSearch: Bool {
        true
    }

    func mediaItem(id: String) async throws -> MediaItem {
        try title(id)
    }

    func libraryID(for _: MediaItem) async throws -> String? {
        "1"
    }

    func searchSubtitles(
        itemID _: String,
        language _: String,
        hearingImpaired _: Bool,
        forced _: Bool,
        title _: String?,
    ) async throws -> [RemoteSubtitleResult] {
        calls.append("searchSubtitles")
        return []
    }

    func installSubtitle(itemID _: String, result _: RemoteSubtitleResult) async throws {
        calls.append("installSubtitle")
    }

    func details(for media: MediaItem) async throws -> MediaDetailContent {
        MediaDetailContent(
            media: media,
            parentSeries: overCeiling,
            onDeck: unrated,
            seasons: titles,
            episodes: titles,
            cast: [],
            relatedHubs: hubs,
        )
    }

    func fileInfo(for _: MediaItem) async throws -> MediaFileInfo? {
        nil
    }

    func fetchExtras(for _: MediaItem) async throws -> [MediaItem] {
        titles
    }

    func otherEditions(of _: MediaItem) async throws -> [MediaItem] {
        titles
    }

    func seasons(for _: MediaItem) async throws -> [MediaItem] {
        titles
    }

    func episodes(for _: MediaItem, seriesID _: String?) async throws -> [MediaItem] {
        titles
    }

    func allEpisodes(for _: MediaItem) async throws -> [MediaItem] {
        titles
    }

    func setPlayed(_: Bool, itemID _: String) async throws {}

    func isWatchlisted(_: MediaItem) async throws -> Bool {
        calls.append("isWatchlisted")
        return false
    }

    func setWatchlisted(_: Bool, media _: MediaItem) async throws {
        calls.append("setWatchlisted")
    }

    func trackSelection(itemID _: String, versionID _: String?) async throws -> MediaTrackSelection {
        throw FakeProviderError.reachedProvider
    }

    func selectAudioTrack(id _: Int, itemID _: String, versionID _: String?) async throws {}

    func selectSubtitleTrack(id _: Int?, itemID _: String, versionID _: String?) async throws {}

    func collectionItems(id _: String) async throws -> [MediaDisplayItem] {
        displayTitles
    }

    func person(id: String) async throws -> Person {
        Person(id: id, name: "Person", thumbPath: nil)
    }

    func personMedia(id _: String) async throws -> [MediaDisplayItem] {
        displayTitles
    }

    // MediaFavoritesService

    var supportsFavorites: Bool {
        true
    }

    func favorites() async throws -> [MediaItem] {
        titles
    }

    func isFavorite(_: MediaItem) async throws -> Bool {
        false
    }

    func setFavorite(_: Bool, media _: MediaItem) async throws {}

    // MediaPlaylistService

    func playlistEntries(id _: String) async throws -> [PlaylistEntry] {
        FakeTitles.entries(titles)
    }

    func canEdit(_: PlaylistMediaItem) async throws -> Bool {
        calls.append("canEdit")
        return true
    }

    func editablePlaylists() async throws -> [PlaylistMediaItem] {
        calls.append("editablePlaylists")
        return [FakeTitles.playlist]
    }

    func createPlaylist(title _: String, itemID _: String) async throws {
        calls.append("createPlaylist")
    }

    func add(itemID _: String, toPlaylist _: String) async throws {
        calls.append("add")
    }

    func remove(_: PlaylistEntry, fromPlaylist _: String) async throws {
        calls.append("remove")
    }

    func move(_: PlaylistEntryMove, inPlaylist _: String) async throws {
        calls.append("move")
    }

    func rename(playlistID _: String, to _: String) async throws {
        calls.append("rename")
    }

    func delete(playlistID _: String) async throws {
        calls.append("delete")
    }

    // MediaPlaybackService

    var serverAccessGeneration: Int {
        0
    }

    /// Blocked titles first, so filtering has to move the current position.
    private var queueOrder: [MediaItem] {
        [overCeiling, unrated, allowed, adultOnly]
    }

    func queue(startingWith itemID: String, kind _: MediaKind, shuffle: Bool) async throws -> PlaybackQueue {
        PlaybackQueue(media: queueOrder, startingAt: itemID, shuffle: shuffle)
    }

    func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue {
        PlaybackQueue(media: queueOrder, startingAt: media.id, shuffle: shuffle)
    }

    func queue(playlistID _: String, startingWith entry: PlaylistEntry) async throws -> PlaybackQueue {
        PlaybackQueue(media: queueOrder, startingAt: entry.media.id, shuffle: false)
    }

    func prepare(
        media: MediaItem,
        resume _: Bool,
        quality _: TranscodeQualityPreset,
        trackPreference _: MediaTrackPreference?,
        version _: MediaVersionRequest,
    ) async throws -> PlaybackPlan {
        calls.append("prepare:\(media.id)")
        throw FakeProviderError.reachedProvider
    }

    func release(plan _: PlaybackPlan) async {}

    func externalPlaybackTarget(
        for _: MediaItem,
        version _: MediaVersionRequest,
    ) async throws -> ExternalPlaybackTarget {
        calls.append("externalPlaybackTarget")
        throw FakeProviderError.reachedProvider
    }

    func reportStarted(
        plan _: PlaybackPlan,
        position _: TimeInterval,
        isPaused _: Bool,
        currentSelection _: PlaybackStreamSelection?,
    ) async throws {}

    func reportProgress(
        plan _: PlaybackPlan,
        position _: TimeInterval,
        isPaused _: Bool,
        currentSelection _: PlaybackStreamSelection?,
    ) async throws {}

    func reportStopped(
        plan _: PlaybackPlan,
        position _: TimeInterval,
        currentSelection _: PlaybackStreamSelection?,
    ) async throws {}

    func externalSubtitles(media _: MediaItem) async throws -> [PlayerExternalSubtitle] {
        []
    }

    func reportItemPlayback(
        itemID _: String,
        state _: ItemPlaybackReportState,
        position _: TimeInterval,
        duration _: TimeInterval?,
        isPaused _: Bool,
    ) async throws {}

    func pushItemPosition(itemID _: String, position _: TimeInterval, duration _: TimeInterval?, at _: Date) async throws {}

    func markItemWatched(itemID _: String, at _: Date) async throws {}

    func serverWatchState(itemID _: String) async throws -> ServerItemWatchState {
        ServerItemWatchState(viewOffset: nil, viewCount: 0, isPlayed: false, lastViewedAt: nil)
    }

    func serverAccessRecoveryError(from _: Error) -> MediaServerAccessRecoveryError? {
        nil
    }

    func recoverServerAccessIfUnauthorized() async throws -> Bool {
        false
    }

    func forceServerAccessRecovery() async throws {}

    // MediaTrackSelectionMemoryService

    func enableTrackSelectionMemory(for _: PlaybackTrackKind) async throws {
        calls.append("enableTrackSelectionMemory")
    }

    // MediaLiveTVService

    var dvr: (any MediaDVRService)? {
        nil
    }

    var supportsServerCaptureBuffer: Bool {
        true
    }

    func isAvailable() async throws -> Bool {
        calls.append("liveTV.isAvailable")
        return true
    }

    func channels() async throws -> [LiveTVChannel] {
        calls.append("liveTV.channels")
        return []
    }

    func programs(from _: Date, to _: Date) async throws -> [LiveTVProgram] {
        calls.append("liveTV.programs")
        return []
    }

    func onNow() async throws -> [LiveTVOnNowSection] {
        calls.append("liveTV.onNow")
        return []
    }

    func setFavorite(_: Bool, channel _: LiveTVChannel) async throws {
        calls.append("liveTV.setFavorite")
    }

    func reorderFavorites(_: [LiveTVChannel]) async throws {
        calls.append("liveTV.reorderFavorites")
    }

    func startPlayback(
        channel _: LiveTVChannel,
        route _: LiveTVRoutePreference,
    ) async throws -> any LiveTVPlaybackSession {
        calls.append("liveTV.startPlayback")
        throw FakeProviderError.reachedProvider
    }

    // MediaDownloadService

    func prepareDownload(
        itemID: String,
        quality: TranscodeQualityPreset,
        tracks _: MediaTrackPreference,
        version _: MediaVersionRequest,
    ) async throws -> MediaDownloadPreparation {
        try MediaDownloadPreparation(
            media: title(itemID),
            requestedQuality: quality,
            effectiveQuality: quality,
            request: nil,
            remoteReference: .jellyfin(playSessionID: "session-\(itemID)"),
            sidecars: [],
            audioTitle: nil,
            subtitleTitle: nil,
            versionID: nil,
            versionLabel: nil,
        )
    }

    func refreshDownloadPreparation(
        _: MediaDownloadRemoteReference,
    ) async throws -> MediaDownloadPreparationUpdate {
        .preparing(progress: nil)
    }

    func downloadSidecars(
        itemID _: String,
        tracks _: MediaTrackPreference,
        versionID _: String?,
        isTranscoded _: Bool,
    ) async throws -> [MediaDownloadSidecar] {
        []
    }

    func cancelDownloadPreparation(_ reference: MediaDownloadRemoteReference) async {
        if case let .jellyfin(playSessionID) = reference {
            calls.append("cancelDownloadPreparation:\(playSessionID)")
        }
    }

    func downloadableItems(itemID _: String, kind _: MediaKind) async throws -> [MediaItem] {
        titles
    }

    // MediaAuthorizationService

    var authorization: MediaAuthorization {
        .plex(isAdministrator: true, allowsMediaDeletion: true)
    }
}

/// The base library of both fakes: its paged listing is the provider's long listing.
@MainActor
private class FakeLibrary: MediaLibraryService {
    let provider: FakeProvider

    init(provider: FakeProvider) {
        self.provider = provider
    }

    func libraries() async throws -> [Library] {
        [Library(id: "1", title: "Movies", type: .movie, sectionId: 1, server: FakeTitles.server)]
    }

    /// Ignored by the boundary, which rebuilds the preview from allowed titles.
    func preview(for _: Library) async throws -> LibraryPreview? {
        LibraryPreview(artworks: provider.blockedTitles.map { FakeTitles.artwork(for: $0.id) }, itemCount: 999)
    }

    func recommended(in _: Library, mergesNextUp _: Bool) async throws -> [Hub] {
        [
            FakeTitles.hub(id: "mixed", items: provider.displayTitles),
            FakeTitles.hub(id: "blocked-only", items: provider.blockedTitles.map(MediaDisplayItem.playable)),
        ]
    }

    func items(
        in _: Library,
        parentID _: String?,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        MediaPage(
            items: provider.listingPage(start: startIndex, limit: limit).map(MediaDisplayItem.playable),
            startIndex: startIndex,
            totalCount: provider.listing.count,
        )
    }

    func collections(in _: Library) async throws -> [CollectionMediaItem] {
        []
    }

    func playlists(in _: Library) async throws -> [PlaylistMediaItem] {
        []
    }
}

@MainActor
private final class FakePlexLibrary: FakeLibrary, PlexAdvancedLibraryService {
    /// A folder, then the long listing.
    func advancedBrowse(
        path _: String,
        queryItems _: [URLQueryItem],
        startIndex: Int,
        limit: Int,
    ) async throws -> PlexAdvancedBrowsePage {
        let folder = LibraryBrowseItem.folder(LibraryBrowseFolderItem(id: "folder", key: "/folder", title: "Folder"))
        let all = [folder] + provider.listing.map { LibraryBrowseItem.media(.playable($0)) }
        let items = startIndex < all.count ? Array(all[startIndex ..< min(startIndex + limit, all.count)]) : []
        return PlexAdvancedBrowsePage(items: items, totalCount: all.count, meta: nil)
    }

    func filterOptions(path _: String, queryItems _: [URLQueryItem]) async throws -> [PlexFilterDirectory] {
        []
    }

    func sectionCharacters(path _: String, queryItems _: [URLQueryItem]) async throws -> [PlexAdvancedSectionCharacter] {
        [PlexAdvancedSectionCharacter(title: "A", size: provider.listing.count)]
    }

    func collectionCharacters(sectionID _: Int) async throws -> [PlexAdvancedSectionCharacter] {
        [PlexAdvancedSectionCharacter(title: "A", size: provider.listing.count)]
    }

    /// Reports no total, like servers that leave it out: the listing ends on a short page.
    func collectionPage(sectionID _: Int, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        MediaPage(
            items: provider.listingPage(start: startIndex, limit: limit).map(MediaDisplayItem.playable),
            startIndex: startIndex,
            totalCount: nil,
        )
    }
}

@MainActor
private final class FakeBrowseLibrary: FakeLibrary, AdvancedLibraryBrowseService {
    func browseItems(
        in _: Library,
        parentID _: String?,
        query _: LibraryBrowseQuery,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        MediaPage(
            items: provider.listingPage(start: startIndex, limit: limit).map(MediaDisplayItem.playable),
            startIndex: startIndex,
            totalCount: provider.listing.count,
        )
    }

    func browseFilterOptions(in _: Library) async throws -> LibraryBrowseFilterOptions {
        throw FakeProviderError.reachedProvider
    }
}

// MARK: - Protocol sources

private enum ProviderProtocolSources {
    /// Every protocol declared in these files must be reviewed.
    static let allProtocolFiles = [
        "Core/Services/Protocols/MediaServiceProtocols.swift",
        "Core/Services/MediaServices.swift",
    ]

    /// Optional abilities that screens look for on `MediaServices.library`.
    static let namedProtocols = [
        ("Core/Providers/Plex/PlexAdvancedLibraryService.swift", "PlexAdvancedLibraryService"),
        ("Core/Features/Library/LibraryBrowseModels.swift", "AdvancedLibraryBrowseService"),
    ]

    /// `PlinxApp/`, from this file's location in the repository.
    static var appDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static func read(_ relativePath: String) throws -> String {
        try String(contentsOf: appDirectory.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

/// Reads protocol requirements from Swift source as selectors, e.g. `queue(startingWith:kind:shuffle:)` or `flag`.
enum ProtocolRequirementParser {
    static func protocolNames(in source: String) -> [String] {
        let code = strippingComments(source)
        let regex = try! NSRegularExpression(pattern: #"(?m)^\s*(?:@\w+\s+)*(?:public\s+|internal\s+)?protocol\s+(\w+)"#)
        return regex.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap { match in
            Range(match.range(at: 1), in: code).map { String(code[$0]) }
        }
    }

    static func requirements(of protocolName: String, in source: String) -> Set<String> {
        let code = strippingComments(source)
        guard let body = body(of: protocolName, in: code) else { return [] }
        let regex = try! NSRegularExpression(pattern: #"\b(func|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        var requirements: Set<String> = []
        for match in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let kindRange = Range(match.range(at: 1), in: body),
                  let nameRange = Range(match.range(at: 2), in: body)
            else { continue }
            let name = String(body[nameRange])
            if body[kindRange] == "var" {
                requirements.insert(name)
            } else if let parameters = parameterList(in: body, after: nameRange.upperBound) {
                let labels = splitTopLevel(parameters).compactMap(label)
                requirements.insert("\(name)(\(labels.map { "\($0):" }.joined()))")
            }
        }
        return requirements
    }

    private static func strippingComments(_ source: String) -> String {
        let withoutBlocks = source.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#,
            with: "",
            options: .regularExpression,
        )
        return withoutBlocks
            .components(separatedBy: .newlines)
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
    }

    /// The text between the protocol's braces.
    private static func body(of protocolName: String, in code: String) -> String? {
        let pattern = #"\bprotocol\s+"# + NSRegularExpression.escapedPattern(for: protocolName) + #"\b[^{]*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
              let range = Range(match.range, in: code)
        else { return nil }
        var depth = 1
        var index = range.upperBound
        while index < code.endIndex {
            switch code[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(code[range.upperBound ..< index])
                }
            default: break
            }
            index = code.index(after: index)
        }
        return nil
    }

    /// The text inside the parentheses that follow a function name, skipping generic parameters.
    private static func parameterList(in text: String, after position: String.Index) -> String? {
        var index = position
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        if index < text.endIndex, text[index] == "<" {
            var depth = 0
            while index < text.endIndex {
                if text[index] == "<" { depth += 1 }
                if text[index] == ">" { depth -= 1 }
                index = text.index(after: index)
                if depth == 0 { break }
            }
        }
        guard index < text.endIndex, text[index] == "(" else { return nil }
        let start = text.index(after: index)
        var depth = 1
        index = start
        while index < text.endIndex {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return String(text[start ..< index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Splits on commas outside nested parentheses, brackets and generic arguments.
    private static func splitTopLevel(_ parameters: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var previous: Character?
        for character in parameters {
            switch character {
            case "(", "[", "<":
                depth += 1
            case ")", "]":
                depth -= 1
            case ">" where previous != "-":
                depth -= 1
            case "," where depth == 0:
                parts.append(current)
                current = ""
                previous = character
                continue
            default:
                break
            }
            current.append(character)
            previous = character
        }
        parts.append(current)
        return parts
    }

    /// The argument label of one parameter declaration, `_` included.
    private static func label(_ parameter: String) -> String? {
        let trimmed = parameter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let colon = trimmed.firstIndex(of: ":") else { return nil }
        return trimmed[..<colon].split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
