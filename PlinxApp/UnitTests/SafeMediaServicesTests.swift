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
//      protocol declarations from source (with the offline caches the wrappers
//      expose and the account preferences `MediaServices` stores) and fails
//      when a requirement (or a whole protocol) is missing from
//      `SafeMediaServices.reviewedRequirements`, or when that table lists one
//      that no longer exists. `test_everyServiceMediaServicesStoresIsReviewed`
//      fails when `MediaServices` stores a service of a protocol not reviewed.
//   2. `test_everyFilteredRequirementHasAContentProbe` fails when a `.filtered`
//      requirement has no entry in `contentProbes` below, and
//      `test_everyGatedRequirementHasAParentOnlyProbe` when a `.gated` one has
//      no entry in `gatedProbes`.
//   3. `test_blockedTitlesNeverLeaveTheBoundary` runs every content probe and
//      fails if a blocked title comes out, or if a probe returns no allowed
//      title (so a probe cannot pass by returning nothing).
//      `test_everyParentOnlyRequirementIsRefusedWhileLockedAndAnsweredOnceUnlocked`
//      runs every parent-only probe against a provider and management service
//      that answer as an administrator's server would.
//
// Adding a provider method therefore means: implement it in the wrapper, list
// it in `reviewedRequirements`, and, if it returns titles or is parent-only,
// add a probe here.
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

    /// `MediaServices` also stores services it does not pass through `SafeMediaServices` (`accountPreferences`), and
    /// screens read them directly. The protocol of every stored service must be reviewed like the provider protocols.
    func test_everyServiceMediaServicesStoresIsReviewed() throws {
        let source = try ProviderProtocolSources.read(ProviderProtocolSources.mediaServicesFile)
        let stored = ProtocolRequirementParser.existentialProperties(of: "MediaServices", in: source)
        XCTAssertEqual(stored["home"], ["MediaHomeService"], "Parsed the stored services")
        XCTAssertEqual(stored["accountPreferences"], ["AccountPreferencesService"], "Parsed the optional ones too")

        let reviewed = Set(SafeMediaServices.reviewedRequirements.keys)
        for (property, protocols) in stored.sorted(by: { $0.key < $1.key }) {
            for name in protocols {
                XCTAssertTrue(
                    reviewed.contains(name),
                    "MediaServices.\(property) is a \(name), which SafeMediaServices.reviewedRequirements does not review",
                )
            }
        }
    }

    func test_parserReadsExistentialProperties() {
        let source = """
        @MainActor
        final class Sample {
            let home: any MediaHomeService
            @ObservationIgnored var preferences: (any AccountPreferencesService)?
            private let library: any MediaLibraryService & PlexAdvancedLibraryService
            let count: Int
            private(set) var revision = 0
            // let commented: any Commented
            var computed: Int { 0 }
            init(parameter: any MediaDetailService) {
                let local: any MediaPlaybackService = parameter as! any MediaPlaybackService
            }
            struct Nested {
                let nested: any MediaFavoritesService
            }
        }
        """
        XCTAssertEqual(
            ProtocolRequirementParser.existentialProperties(of: "Sample", in: source),
            [
                "home": ["MediaHomeService"],
                "preferences": ["AccountPreferencesService"],
                "library": ["MediaLibraryService", "PlexAdvancedLibraryService"],
            ],
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

    func test_everyGatedRequirementHasAParentOnlyProbe() {
        let gated = SafeMediaServices.reviewedRequirements.flatMap { name, requirements in
            requirements.filter { $0.value == .gated }.map { "\(name).\($0.key)" }
        }
        let probes = Set(gatedProbes.keys)
        XCTAssertEqual(Set(gated).subtracting(probes).sorted(), [], "Gated requirements without a probe")
        XCTAssertEqual(probes.subtracting(gated).sorted(), [], "Probes for requirements not marked gated")
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
        let expected = fixture.provider.listing.filter { FakeTitles.isAllowed($0.id) }.map(\.id)

        for listing in pagedListings(of: fixture) {
            for limit in [4, 7, 40] {
                let ids = try await pageThrough(limit: limit, name: listing.name, listing.load)
                XCTAssertEqual(ids, listing.leadingFolders + expected, "\(listing.name) with pages of \(limit)")
            }
        }
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

    /// The caller's title passed, but the plan the server returns names a title above the ceiling: the same title
    /// re-rated since it was loaded, or another one. The boundary judges the plan's title, releases the server
    /// session it opened, and refuses the plan.
    func test_planForATitleReratedOnTheServerIsReleasedAndRefused() async throws {
        let fixture = Fixture()
        let allowed = fixture.provider.allowed
        let served = [
            FakeTitles.media(allowed.id, rating: "R"),
            fixture.provider.overCeiling,
        ]
        for media in served {
            fixture.provider.preparedMedia[allowed.id] = media
            await assertThrows(.blocked) {
                _ = try await fixture.plex.playback.prepare(
                    media: allowed,
                    resume: false,
                    quality: .original,
                    trackPreference: nil,
                    version: .automatic,
                )
            }
        }
        XCTAssertEqual(
            fixture.provider.calls,
            ["prepare:allowed", "release:allowed", "prepare:allowed", "release:over-ceiling"],
            "Each refused plan was released on the server",
        )
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

    // MARK: - Tightening the policy

    /// A listing gathered under a permissive policy is never reused once a parent tightens it: the next request for a
    /// later page starts the listing over under the stricter policy, holds no title only the old policy allowed, and is
    /// indexed and counted in the stricter listing.
    func test_tighterPolicyAppliesToLaterPagesOfListingsGatheredUnderTheOldOne() async throws {
        let fixture = Fixture()
        fixture.provider.listing = TighteningFixture.listing
        let limit = 10
        let start = 20

        for listing in pagedListings(of: fixture) {
            fixture.gate.policy = TighteningFixture.permissive
            var gathered: [String] = []
            var lastPermissivePage: PageResult?
            for pageStart in stride(from: 0, through: start, by: limit) {
                let page = try await listing.load(pageStart, limit)
                gathered += page.ids
                lastPermissivePage = page
            }
            let permitted = listing.leadingFolders + TighteningFixture.permittedIDs
            XCTAssertEqual(gathered, Array(permitted.prefix(start + limit)), "\(listing.name) under the permissive policy")
            let gatheredPage = try XCTUnwrap(lastPermissivePage)
            XCTAssertTrue(
                gatheredPage.ids.contains(where: TighteningFixture.isDroppedWhenTightened),
                "\(listing.name): the gathered page at \(start) holds titles the strict policy blocks",
            )

            fixture.gate.policy = TighteningFixture.strict
            let kept = listing.leadingFolders + TighteningFixture.keptIDs
            let page = try await listing.load(start, limit)
            XCTAssertEqual(
                page.ids.filter(TighteningFixture.isDroppedWhenTightened),
                [],
                "\(listing.name) served titles only the old policy allowed",
            )
            XCTAssertEqual(page.startIndex, start, "\(listing.name) page start")
            XCTAssertEqual(page.ids, Array(kept[start ..< start + limit]), "\(listing.name) is indexed in the stricter listing")
            let total = try XCTUnwrap(page.total, "\(listing.name) reports a count")
            XCTAssertGreaterThanOrEqual(total, start + page.ids.count, "\(listing.name) count covers the page")
            XCTAssertLessThanOrEqual(total, kept.count, "\(listing.name) counts no title the stricter policy blocks")

            // Paged from the start, the stricter listing holds exactly the titles it allows.
            let tightened = try await pageThrough(limit: limit, name: "\(listing.name), tightened", listing.load)
            XCTAssertEqual(tightened, kept, "\(listing.name) after tightening")
        }
    }

    /// The offline caches are judged when they are read, so a home or detail page cached under a permissive policy
    /// loses whatever a stricter one blocks.
    func test_tighterPolicyAppliesToTheOfflineCaches() throws {
        let fixture = Fixture()
        let keptG = FakeTitles.media("kept-g", rating: "G")
        fixture.provider.extraTitles = [keptG]
        let home = try XCTUnwrap(fixture.plex.home as? any OfflineHomeCacheReading)
        let detail = try XCTUnwrap(fixture.plex.detail as? any OfflineDetailCacheReading)

        fixture.gate.policy = TighteningFixture.permissive
        let permissiveHome = try XCTUnwrap(home.cachedHome())
        XCTAssertEqual(permissiveHome.rows.map(\.id), ["mixed", "blocked-only"])
        XCTAssertTrue(FakeTitles.ids(in: permissiveHome.rows).contains("over-ceiling"))
        XCTAssertNotNil(detail.cachedDetails(for: fixture.provider.allowed))

        fixture.gate.policy = TighteningFixture.strict
        let strictHome = try XCTUnwrap(home.cachedHome())
        XCTAssertEqual(strictHome.rows.map(\.id), ["mixed"], "A cached row the stricter policy empties is dropped")
        XCTAssertEqual(
            FakeTitles.ids(in: strictHome.rows),
            ["kept-g"],
            "Cached titles and copies only the old policy allowed are dropped",
        )
        XCTAssertNil(
            detail.cachedDetails(for: fixture.provider.allowed),
            "No cached page opens for a title the stricter policy blocks",
        )
        let content = try XCTUnwrap(detail.cachedDetails(for: keptG))
        XCTAssertNil(content.parentSeries)
        XCTAssertNil(content.onDeck)
        XCTAssertEqual(content.seasons.map(\.id), ["kept-g"])
        XCTAssertEqual(content.episodes.map(\.id), ["kept-g"])
        XCTAssertEqual(content.relatedHubs.flatMap { $0.items.map(\.id) }, ["kept-g"])
    }

    /// The home checks the rows it loaded under an older policy against the current one, so lowering the ceiling hides
    /// them at once, before any reload. The sample library supplies the rows through the production session,
    /// `ServerRegistry` and `SafeMediaServices`; rows read from the offline cache reach `rows` the same way.
    func test_homeRowsLoadedUnderAPermissivePolicyAreHiddenWhenItTightens() async throws {
        defer { DemoFixtureBootstrap.stop() }
        let originalPolicy = ContentSafetyGate.shared.policy
        defer { ContentSafetyGate.shared.policy = originalPolicy }
        let (session, settings) = try await startIsolatedSampleLibrary()
        let home = HomeViewModel(sessionManager: session, settingsManager: settings)

        ContentSafetyGate.shared.policy = TighteningFixture.permissive
        await home.reload()
        let loaded = FakeTitles.ids(in: home.rows)
        XCTAssertTrue(loaded.contains("moonbound"), "The PG sample movie is on the home under the permissive policy: \(loaded)")

        ContentSafetyGate.shared.policy = TighteningFixture.strict
        let shown = FakeTitles.ids(in: home.rows)
        XCTAssertFalse(shown.contains("moonbound"), "A row loaded under the permissive policy is checked again")
        XCTAssertTrue(Set(shown).isSubset(of: Set(loaded)), "The home was not reloaded")
        let gate = ContentSafetyGate.shared
        for row in home.rows {
            for item in row.items {
                XCTAssertTrue(gate.isAllowed(item), "\(row.id) still shows \(item.id)")
            }
            for copy in row.copies.values.joined() {
                XCTAssertTrue(gate.isAllowed(copy), "\(row.id) still holds a copy of \(copy.id)")
            }
        }
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

    /// Both servers build a container's artwork from all of its entries, blocked ones included (a Plex composite, a
    /// Jellyfin collage), and count them all. Containers leave the boundary without that artwork and those counts.
    func test_containersAreListedWithoutTheServerArtworkOfTheirEntries() async throws {
        let fixture = Fixture()
        fixture.provider.listedCollections = [ContainerFixture.collection]
        fixture.provider.listedPlaylists = [ContainerFixture.playlist]
        fixture.provider.containers = [.collection(ContainerFixture.collection), .playlist(ContainerFixture.playlist)]
        let services = fixture.plex

        let collections = try await services.library.collections(in: fixture.library)
        XCTAssertEqual(collections.map(\.id), ["collection"], "Containers stay listed")
        XCTAssertEqual(collections.map(\.thumbPath), [nil])
        XCTAssertEqual(collections.map(\.childCount), [nil])
        let playlists = try await services.library.playlists(in: fixture.library)
        XCTAssertEqual(playlists.map(\.id), ["playlist"])
        XCTAssertEqual(playlists.map(\.compositePath), [nil])
        XCTAssertEqual(playlists.map(\.leafCount), [nil])
        XCTAssertEqual(playlists.map(\.duration), [nil])

        let hub = FakeTitles.hub(id: "mixed", items: [])
        let listings: [(String, [MediaDisplayItem])] = try await [
            ("search", services.search.search(query: "anything", kinds: [])),
            ("hub page", services.home.items(in: hub, startIndex: 0, limit: 500).items),
            ("recommended", services.library.recommended(in: fixture.library, mergesNextUp: false).flatMap(\.items)),
            ("person", services.detail.personMedia(id: "person")),
        ]
        for (name, items) in listings {
            let containers = items.filter { $0.playableItem == nil }
            XCTAssertEqual(containers.map(\.id), ["collection", "playlist"], "\(name) lists the containers")
            XCTAssertEqual(containers.compactMap(\.thumbPath), [], "\(name) draws no server composite")
            XCTAssertEqual(containers.compactMap(\.preferredThumbPath), [], "\(name) draws no server composite")
            XCTAssertEqual(containers.compactMap(\.secondaryLabel), [], "\(name) shows no server count")
        }
        XCTAssertNil(fixture.gate.shown(.collection(ContainerFixture.collection))?.thumbPath)
    }

    // MARK: - Seasons and episodes

    /// Servers rarely rate seasons and episodes (Jellyfin almost never), so families allow unrated content to see TV
    /// at all. An unrated episode or season of a TV-MA series must stay blocked then, on every path that returns it.
    func test_unratedEpisodesOfABlockedSeriesStayBlockedWhenUnratedContentIsAllowed() async throws {
        let fixture = Fixture()
        fixture.gate.policy = .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: true)
        fixture.provider.seriesCatalog = SeriesFixture.catalog
        fixture.provider.extraTitles = SeriesFixture.children
        let services = fixture.plex
        let expected = SeriesFixture.allowedChildIDs

        let rows = try await services.home.loadWatchingRows(hiddenLibraryIDs: [], mergesNextUp: true)
        XCTAssertEqual(SeriesFixture.childIDs(in: FakeTitles.ids(in: rows)), expected, "Continue Watching and Next Up")
        let found = try await services.search.search(query: "anything", kinds: [])
        XCTAssertEqual(SeriesFixture.childIDs(in: found.map(\.id)), expected, "search")
        let hub = FakeTitles.hub(id: "mixed", items: [])
        let hubPage = try await services.home.items(in: hub, startIndex: 0, limit: 500)
        XCTAssertEqual(SeriesFixture.childIDs(in: hubPage.items.map(\.id)), expected, "hub page")
        let episodes = try await services.detail.episodes(for: SeriesFixture.season, seriesID: nil)
        XCTAssertEqual(SeriesFixture.childIDs(in: episodes.map(\.id)), expected, "season page")
        let favorites = try await services.favorites.favorites()
        XCTAssertEqual(SeriesFixture.childIDs(in: favorites.map(\.id)), expected, "favorites")
        let entries = try await services.playlists.playlistEntries(id: "playlist")
        XCTAssertEqual(SeriesFixture.childIDs(in: entries.map(\.media.id)), expected, "playlist entries")
        let downloadable = try await services.downloads.downloadableItems(itemID: "season", kind: .season)
        XCTAssertEqual(SeriesFixture.childIDs(in: downloadable.map(\.id)), expected, "season downloads")
        let queue = try await services.playback.queue(startingWith: "ep-kids-unrated", kind: .episode, shuffle: false)
        XCTAssertEqual(SeriesFixture.childIDs(in: queue.items.map(\.media.id)), expected, "playback queue")

        for blocked in SeriesFixture.blockedChildIDs {
            await assertThrows(.blocked) { _ = try await services.detail.mediaItem(id: blocked) }
            await assertThrows(.blocked) {
                _ = try await services.playback.queue(startingWith: blocked, kind: .episode, shuffle: false)
            }
        }
        let allowed = try await services.detail.mediaItem(id: "ep-kids-unrated")
        XCTAssertEqual(allowed.id, "ep-kids-unrated")

        // The checks after the boundary (launcher, player, downloads) judge against what the boundary learned.
        let mature = try XCTUnwrap(SeriesFixture.children.first { $0.id == "ep-mature-unrated" })
        XCTAssertFalse(fixture.gate.isAllowed(mature))
        XCTAssertEqual(
            fixture.gate.decision(for: mature),
            .rejected(reason: .ratingExceedsMax(itemRating: .tvMa, maxAllowed: .tvPg)),
        )
        // Each series is looked up once, however many requests need it; a lookup that failed is not retried at once.
        XCTAssertEqual(
            fixture.provider.lookedUp.filter { $0.hasPrefix("show-") }.sorted(),
            ["show-impostor", "show-kids", "show-mature", "show-missing"],
        )
    }

    /// An episode without a rating of its own is judged by its series' rating, not as unrated content.
    func test_anUnratedEpisodeTakesItsSeriesRating() async throws {
        let fixture = Fixture()
        fixture.gate.policy = .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        fixture.provider.seriesCatalog = SeriesFixture.catalog
        fixture.provider.extraTitles = SeriesFixture.children

        let found = try await fixture.plex.search.search(query: "anything", kinds: [])
        XCTAssertEqual(SeriesFixture.childIDs(in: found.map(\.id)), SeriesFixture.allowedChildIDs)
        let orphan = try XCTUnwrap(SeriesFixture.children.first { $0.id == "ep-orphan-unrated" })
        XCTAssertEqual(fixture.gate.decision(for: orphan), .rejected(reason: .missingRating))
    }

    /// A series that a listing returns with its rating is not looked up again.
    func test_aSeriesListedWithItsEpisodesIsNotLookedUp() async throws {
        let fixture = Fixture()
        fixture.gate.policy = .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: true)
        fixture.provider.seriesCatalog = SeriesFixture.catalog
        let kidsEpisode = try XCTUnwrap(SeriesFixture.children.first { $0.id == "ep-kids-unrated" })
        let matureEpisode = try XCTUnwrap(SeriesFixture.children.first { $0.id == "ep-mature-unrated" })
        fixture.provider.extraTitles = [SeriesFixture.kids, kidsEpisode, SeriesFixture.mature, matureEpisode]

        let found = try await fixture.plex.search.search(query: "anything", kinds: [])
        XCTAssertEqual(
            found.map(\.id).filter { $0.hasPrefix("show-") || $0.hasPrefix("ep-") },
            ["show-kids", "ep-kids-unrated"],
        )
        XCTAssertEqual(fixture.provider.lookedUp, [])
    }

    /// On iOS the learned ratings are kept on the device, so a download is still judged against its series offline.
    func test_learnedSeriesRatingsAreKeptForOfflineChecks() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeriesRatings-\(UUID().uuidString).json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = SeriesRatingStore(fileURL: fileURL)
        let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: true)
        let online = ContentSafetyGate(policy: policy, seriesRatingStore: store)
        await online.learnSeries(of: SeriesFixture.children) { seriesID in
            guard let series = SeriesFixture.catalog.first(where: { $0.id == seriesID }) else {
                throw FakeProviderError.notFound
            }
            return series
        }
        XCTAssertEqual(online.filter(SeriesFixture.children).map(\.id), SeriesFixture.allowedChildIDs)
        online.saveSeriesRatings()

        // The next launch, without the server.
        let offline = ContentSafetyGate(policy: policy, seriesRatingStore: store)
        XCTAssertEqual(offline.filter(SeriesFixture.children).map(\.id), SeriesFixture.allowedChildIDs)
        XCTAssertEqual(offline.seriesRating(for: SeriesFixture.mature.identity)?.contentRating, "TV-MA")
        XCTAssertEqual(
            offline.seriesRating(for: SeriesFixture.mature.identity)?.isConfirmed,
            false,
            "Read back unconfirmed, so the series is looked up again online",
        )

        // A gate that learned nothing blocks every unrated episode, and judges a rated one on its own rating.
        let unaware = ContentSafetyGate(policy: policy)
        XCTAssertEqual(unaware.filter(SeriesFixture.children).map(\.id), ["ep-mature-rated", "ep-orphan-rated"])
    }

    // MARK: - Parent-only and disabled abilities

    /// Every `.gated` requirement, through `MediaServices`: while the parental gate is locked it is refused, empty or
    /// false and nothing reaches the provider or its management service, although both answer as an administrator's
    /// server would; once a parent unlocks the gate, the provider answers.
    func test_everyParentOnlyRequirementIsRefusedWhileLockedAndAnsweredOnceUnlocked() async throws {
        for (requirement, probe) in gatedProbes.sorted(by: { $0.key < $1.key }) {
            let fixture = Fixture()
            do {
                let answered = try await probe(fixture)
                XCTAssertFalse(answered, "\(requirement) was answered while the gate was locked")
            } catch {
                XCTAssertEqual(
                    error as? ContentSafetyError,
                    .parentApprovalRequired,
                    "\(requirement) failed otherwise while locked: \(error)",
                )
            }
            XCTAssertEqual(fixture.provider.calls, [], "\(requirement) reached the provider while locked")
            XCTAssertEqual(fixture.management.calls, [], "\(requirement) reached server management while locked")

            fixture.gate.isParentUnlocked = true
            do {
                let answered = try await probe(fixture)
                XCTAssertTrue(answered, "\(requirement) did not reach the provider once unlocked")
            } catch {
                XCTFail("\(requirement) failed once unlocked: \(error)")
            }
        }
    }

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
        XCTAssertEqual(fixture.management.calls, [], "Nothing reached server management while locked")

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
        XCTAssertEqual(fixture.management.calls, ["refreshMetadata(itemID:)"])
    }

    /// Hard-fork plan P6: with the gate locked, the card and detail menus get no Manage entry, even on a server the
    /// account administers, and the destructive actions behind it do nothing.
    func test_manageMenuIsEmptyAndRefusedWhileLocked() async {
        let fixture = Fixture()
        let movie = fixture.provider.allowed
        let locked = MediaQuickActions(services: fixture.plex)

        XCTAssertEqual(locked.manageActions(for: movie), [])
        XCTAssertFalse(locked.menuActions(for: movie, canDownload: false, canManage: true).contains(.manage))
        let preparation = await locked.prepareDeletion(of: movie)
        XCTAssertEqual(preparation, .cancelled)
        let deletion = await locked.delete(movie)
        XCTAssertEqual(deletion, .cancelled)
        let unmatch = await locked.unmatch(movie)
        XCTAssertEqual(unmatch, .cancelled)
        let refresh = await locked.refreshMetadata(movie)
        XCTAssertEqual(refresh, .cancelled)

        let deletionModel = MediaDeletionViewModel(item: movie, quickActions: locked)
        await deletionModel.load()
        XCTAssertFalse(deletionModel.canDelete, "The deletion confirmation never offers Delete while locked")
        await deletionModel.delete()
        XCTAssertNotEqual(deletionModel.state, .deleted)
        XCTAssertEqual(fixture.management.calls, [], "Nothing reached server management while locked")

        // The same services list the entries once a parent unlocks, so the empty menu above comes from the gate.
        fixture.gate.isParentUnlocked = true
        let unlocked = MediaQuickActions(services: fixture.plex)
        XCTAssertTrue(unlocked.manageActions(for: movie).contains(.delete))
        XCTAssertTrue(unlocked.menuActions(for: movie, canDownload: false, canManage: true).contains(.manage))
    }

    func test_liveTVAndUnfilteredLetterCountsAreOff() async throws {
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
        let advanced = try XCTUnwrap(services.library as? any PlexAdvancedLibraryService)
        let characters = try await advanced.sectionCharacters(path: "/library/sections/1/firstCharacter", queryItems: [])
        XCTAssertTrue(characters.isEmpty, "Unfiltered letter counts would misplace the filtered listing")
        XCTAssertEqual(fixture.provider.calls, [])
    }

    /// Handing a title to another app would skip every content check and the parent's volume cap. No provider
    /// protocol offers it, so there is no external-player path for the boundary to disable; this keeps it that way.
    func test_noProviderRequirementHandsPlaybackToAnotherApp() throws {
        var requirements: [String] = []
        for file in ProviderProtocolSources.allProtocolFiles {
            let source = try ProviderProtocolSources.read(file)
            for name in ProtocolRequirementParser.protocolNames(in: source) {
                requirements += ProtocolRequirementParser.requirements(of: name, in: source).map { "\(name).\($0)" }
            }
        }
        for (file, name) in ProviderProtocolSources.namedProtocols {
            let source = try ProviderProtocolSources.read(file)
            requirements += ProtocolRequirementParser.requirements(of: name, in: source).map { "\(name).\($0)" }
        }
        let reviewed = SafeMediaServices.reviewedRequirements.flatMap { name, requirements in
            requirements.keys.map { "\(name).\($0)" }
        }

        XCTAssertFalse(requirements.isEmpty, "Parsed no provider requirement")
        let isExternalPlayback = { (selector: String) in selector.lowercased().contains("externalplay") }
        XCTAssertEqual(requirements.filter(isExternalPlayback).sorted(), [], "Provider protocols offer external playback")
        XCTAssertEqual(reviewed.filter(isExternalPlayback).sorted(), [], "The boundary lists an external-playback path")
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
        // Screens read the offline caches by casting these services: the casts find the wrappers, never the provider.
        XCTAssertTrue((fixture.plex.home as? any OfflineHomeCacheReading) is SafeHomeService)
        XCTAssertTrue((fixture.plex.detail as? any OfflineDetailCacheReading) is SafeDetailService)
        XCTAssertTrue(fixture.plex.management is SafeManagementService)
    }

    // MARK: - Jellyfin custom ratings

    /// Jellyfin's `CustomRating` is an admin's override of `OfficialRating`. A title rated above the ceiling that way
    /// stays blocked though its official rating is under it, and a custom rating never loosens a stricter official one.
    func test_jellyfinCustomRatingAboveTheCeilingIsBlocked() throws {
        let gate = ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg, maxTV: .tvY7))
        let raisedOverCeiling = try Self.jellyfinMedia(id: "custom-r", official: "PG", custom: "R")
        let loweredUnderCeiling = try Self.jellyfinMedia(id: "custom-pg", official: "R", custom: "PG")
        let raisedWithinCeiling = try Self.jellyfinMedia(id: "custom-pg-from-g", official: "G", custom: "PG")

        XCTAssertFalse(gate.isAllowed(raisedOverCeiling), "The custom rating is above the ceiling")
        XCTAssertFalse(gate.isAllowed(loweredUnderCeiling), "A custom rating cannot loosen the official one")
        XCTAssertTrue(gate.isAllowed(raisedWithinCeiling))
        XCTAssertEqual(
            gate.filter([raisedOverCeiling, loweredUnderCeiling, raisedWithinCeiling]).map(\.id),
            ["custom-pg-from-g"],
        )
        XCTAssertThrowsError(try gate.requireAllowed(raisedOverCeiling)) { error in
            XCTAssertEqual(error as? ContentSafetyError, .blocked)
        }

        gate.policy = .ratingOnly(maxMovie: .pg, maxTV: .tvY7, allowUnrated: true)
        XCTAssertFalse(gate.isAllowed(raisedOverCeiling), "Allowing unrated titles does not unblock a rated one")
        let customOnly = try Self.jellyfinMedia(id: "custom-only", official: nil, custom: "R")
        XCTAssertFalse(gate.isAllowed(customOnly), "A custom rating on an unrated title is judged, not ignored")
        let customOverUnreadable = try Self.jellyfinMedia(id: "custom-tv-ma", official: "Not Rated", custom: "TV-MA")
        XCTAssertFalse(gate.isAllowed(customOverUnreadable))

        gate.policy = .ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: true)
        let adultCustom = try Self.jellyfinMedia(id: "custom-nc17", official: "PG", custom: "NC-17")
        XCTAssertFalse(gate.isAllowed(adultCustom), "An adult-only custom rating is never allowed")
    }

    private static func jellyfinMedia(id: String, official: String?, custom: String?) throws -> MediaItem {
        var json: [String: Any] = ["Id": id, "Name": id, "Type": "Movie"]
        if let official {
            json["OfficialRating"] = official
        }
        if let custom {
            json["CustomRating"] = custom
        }
        let item = try JSONDecoder().decode(JellyfinItem.self, from: JSONSerialization.data(withJSONObject: json))
        return MediaItem(jellyfinItem: item, server: ServerIdentity(provider: .jellyfin, id: "jellyfin-server"))
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
            let plan = try await fixture.plex.playback.prepare(
                media: fixture.provider.allowed,
                resume: false,
                quality: .original,
                trackPreference: nil,
                version: .automatic,
            )
            XCTAssertEqual(fixture.provider.calls, ["prepare:allowed"], "An allowed plan is kept, not released")
            return [plan.media.id]
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
        // Offline caches, which the home and detail screens read by casting the wrapped services
        probes["OfflineHomeCacheReading.cachedHome()"] = { fixture in
            let cache = try XCTUnwrap(fixture.plex.home as? any OfflineHomeCacheReading)
            let content = try XCTUnwrap(cache.cachedHome(), "The provider's cached home is handed on")
            XCTAssertEqual(content.rows.map(\.id), ["mixed"], "A cached row emptied by filtering is dropped")
            // The ids include each row's copies, so a blocked copy of an allowed title counts as a leak.
            return FakeTitles.ids(in: content.rows)
        }
        probes["OfflineDetailCacheReading.cachedDetails(for:)"] = { fixture in
            let cache = try XCTUnwrap(fixture.plex.detail as? any OfflineDetailCacheReading)
            for blocked in fixture.provider.blockedTitles {
                XCTAssertNil(cache.cachedDetails(for: blocked), "No cached page opens for \(blocked.id)")
            }
            let content = try XCTUnwrap(cache.cachedDetails(for: fixture.provider.allowed))
            XCTAssertNil(content.parentSeries, "A blocked cached series is dropped")
            XCTAssertNil(content.onDeck, "A blocked cached on-deck title is dropped")
            XCTAssertEqual(content.relatedHubs.map(\.id), ["mixed"])
            return [content.media.id]
                + content.seasons.map(\.id)
                + content.episodes.map(\.id)
                + content.relatedHubs.flatMap { $0.items.map(\.id) }
        }
        return probes
    }

    private typealias GatedProbe = @MainActor (Fixture) async throws -> Bool

    /// One probe per `.gated` requirement, keyed `Protocol.selector`. Each makes the request through `MediaServices`
    /// and returns whether the provider answered it: its non-empty or true answer came back, or it recorded the call.
    /// A locked gate must make every probe throw `ContentSafetyError.parentApprovalRequired` or return false.
    private var gatedProbes: [String: GatedProbe] {
        var probes: [String: GatedProbe] = [:]
        // Detail: the watchlist and subtitle downloads
        probes["MediaDetailService.supportsWatchlist"] = { $0.plex.detail.supportsWatchlist }
        probes["MediaDetailService.supportsRemoteSubtitleSearch"] = { $0.plex.detail.supportsRemoteSubtitleSearch }
        probes["MediaDetailService.supportsAdvancedSubtitleSearch"] = { $0.plex.detail.supportsAdvancedSubtitleSearch }
        probes["MediaDetailService.searchSubtitles(itemID:language:hearingImpaired:forced:title:)"] = { fixture in
            let results = try await fixture.plex.detail.searchSubtitles(
                itemID: "allowed",
                language: "en",
                hearingImpaired: false,
                forced: false,
                title: nil,
            )
            return !results.isEmpty
        }
        probes["MediaDetailService.installSubtitle(itemID:result:)"] = { fixture in
            try await fixture.plex.detail.installSubtitle(itemID: "allowed", result: FakeTitles.subtitle)
            return fixture.provider.calls.contains("installSubtitle")
        }
        probes["MediaDetailService.isWatchlisted(_:)"] = { fixture in
            try await fixture.plex.detail.isWatchlisted(fixture.provider.allowed)
        }
        probes["MediaDetailService.setWatchlisted(_:media:)"] = { fixture in
            try await fixture.plex.detail.setWatchlisted(true, media: fixture.provider.allowed)
            return fixture.provider.calls.contains("setWatchlisted")
        }
        // Playlist edits
        probes["MediaPlaylistService.canEdit(_:)"] = { fixture in
            try await fixture.plex.playlists.canEdit(FakeTitles.playlist)
        }
        probes["MediaPlaylistService.editablePlaylists()"] = { fixture in
            let playlists = try await fixture.plex.playlists.editablePlaylists()
            return !playlists.isEmpty
        }
        probes["MediaPlaylistService.createPlaylist(title:itemID:)"] = { fixture in
            try await fixture.plex.playlists.createPlaylist(title: "New", itemID: "allowed")
            return fixture.provider.calls.contains("createPlaylist")
        }
        probes["MediaPlaylistService.add(itemID:toPlaylist:)"] = { fixture in
            try await fixture.plex.playlists.add(itemID: "allowed", toPlaylist: "playlist")
            return fixture.provider.calls.contains("add")
        }
        probes["MediaPlaylistService.remove(_:fromPlaylist:)"] = { fixture in
            try await fixture.plex.playlists.remove(FakeTitles.entry, fromPlaylist: "playlist")
            return fixture.provider.calls.contains("remove")
        }
        probes["MediaPlaylistService.move(_:inPlaylist:)"] = { fixture in
            let move = PlaylistEntryMove(entryID: "entry", index: 0, previousEntryID: nil)
            try await fixture.plex.playlists.move(move, inPlaylist: "playlist")
            return fixture.provider.calls.contains("move")
        }
        probes["MediaPlaylistService.rename(playlistID:to:)"] = { fixture in
            try await fixture.plex.playlists.rename(playlistID: "playlist", to: "Renamed")
            return fixture.provider.calls.contains("rename")
        }
        probes["MediaPlaylistService.delete(playlistID:)"] = { fixture in
            try await fixture.plex.playlists.delete(playlistID: "playlist")
            return fixture.provider.calls.contains("delete")
        }
        // Server rights
        probes["MediaAuthorizationService.authorization"] = { $0.plex.authorization != .denied }
        // Server management
        probes["MediaManagementService.refreshMetadata(itemID:)"] = { fixture in
            try await fixture.plex.management.refreshMetadata(itemID: "allowed")
            return fixture.management.received("refreshMetadata(itemID:)")
        }
        probes["MediaManagementService.supportsAnalyze"] = { $0.plex.management.supportsAnalyze }
        probes["MediaManagementService.analyze(itemID:)"] = { fixture in
            try await fixture.plex.management.analyze(itemID: "allowed")
            return fixture.management.received("analyze(itemID:)")
        }
        probes["MediaManagementService.scanLibrary(id:)"] = { fixture in
            try await fixture.plex.management.scanLibrary(id: "1")
            return fixture.management.received("scanLibrary(id:)")
        }
        probes["MediaManagementService.refreshLibraryMetadata(id:)"] = { fixture in
            try await fixture.plex.management.refreshLibraryMetadata(id: "1")
            return fixture.management.received("refreshLibraryMetadata(id:)")
        }
        probes["MediaManagementService.analyzeLibrary(id:)"] = { fixture in
            try await fixture.plex.management.analyzeLibrary(id: "1")
            return fixture.management.received("analyzeLibrary(id:)")
        }
        probes["MediaManagementService.supportsLibraryTrash"] = { $0.plex.management.supportsLibraryTrash }
        probes["MediaManagementService.emptyLibraryTrash(id:)"] = { fixture in
            try await fixture.plex.management.emptyLibraryTrash(id: "1")
            return fixture.management.received("emptyLibraryTrash(id:)")
        }
        probes["MediaManagementService.artworkKinds(for:)"] = { fixture in
            !fixture.plex.management.artworkKinds(for: fixture.provider.allowed).isEmpty
        }
        probes["MediaManagementService.artworkOptions(for:kind:)"] = { fixture in
            let options = try await fixture.plex.management.artworkOptions(for: fixture.provider.allowed, kind: .poster)
            return !options.isEmpty
        }
        probes["MediaManagementService.selectArtwork(_:for:kind:)"] = { fixture in
            try await fixture.plex.management.selectArtwork(
                ManagementFixture.artworkOption,
                for: fixture.provider.allowed,
                kind: .poster,
            )
            return fixture.management.received("selectArtwork(_:for:kind:)")
        }
        probes["MediaManagementService.uploadArtwork(_:for:kind:)"] = { fixture in
            try await fixture.plex.management.uploadArtwork(
                ManagementFixture.upload,
                for: fixture.provider.allowed,
                kind: .poster,
            )
            return fixture.management.received("uploadArtwork(_:for:kind:)")
        }
        probes["MediaManagementService.deletionImpact(of:)"] = { fixture in
            _ = try await fixture.plex.management.deletionImpact(of: fixture.provider.allowed)
            return fixture.management.received("deletionImpact(of:)")
        }
        probes["MediaManagementService.delete(_:)"] = { fixture in
            try await fixture.plex.management.delete(fixture.provider.allowed)
            return fixture.management.received("delete(_:)")
        }
        probes["MediaManagementService.searchMatches(for:title:year:)"] = { fixture in
            let matches = try await fixture.plex.management.searchMatches(
                for: fixture.provider.allowed,
                title: "allowed",
                year: nil,
            )
            return !matches.isEmpty
        }
        probes["MediaManagementService.applyMatch(_:to:)"] = { fixture in
            try await fixture.plex.management.applyMatch(ManagementFixture.match, to: fixture.provider.allowed)
            return fixture.management.received("applyMatch(_:to:)")
        }
        probes["MediaManagementService.supportsUnmatch"] = { $0.plex.management.supportsUnmatch }
        probes["MediaManagementService.unmatch(itemID:)"] = { fixture in
            try await fixture.plex.management.unmatch(itemID: "allowed")
            return fixture.management.received("unmatch(itemID:)")
        }
        probes["MediaManagementService.editableMetadataFields(for:)"] = { fixture in
            !fixture.plex.management.editableMetadataFields(for: fixture.provider.allowed).isEmpty
        }
        probes["MediaManagementService.loadMetadataDraft(for:)"] = { fixture in
            _ = try await fixture.plex.management.loadMetadataDraft(for: fixture.provider.allowed)
            return fixture.management.received("loadMetadataDraft(for:)")
        }
        probes["MediaManagementService.saveMetadata(_:original:for:)"] = { fixture in
            try await fixture.plex.management.saveMetadata(
                ManagementFixture.draft,
                original: ManagementFixture.draft,
                for: fixture.provider.allowed,
            )
            return fixture.management.received("saveMetadata(_:original:for:)")
        }
        probes["MediaManagementService.metadataSuggestions(for:item:)"] = { fixture in
            let suggestions = try await fixture.plex.management.metadataSuggestions(
                for: .genres,
                item: fixture.provider.allowed,
            )
            return !suggestions.isEmpty
        }
        probes["MediaManagementService.supportsAdvancedSettings(for:)"] = { fixture in
            fixture.plex.management.supportsAdvancedSettings(for: fixture.provider.allowed)
        }
        probes["MediaManagementService.advancedSettings(itemID:)"] = { fixture in
            let settings = try await fixture.plex.management.advancedSettings(itemID: "allowed")
            return !settings.isEmpty
        }
        probes["MediaManagementService.updateAdvancedSetting(_:value:itemID:)"] = { fixture in
            try await fixture.plex.management.updateAdvancedSetting(
                ManagementFixture.setting,
                value: "1",
                itemID: "allowed",
            )
            return fixture.management.received("updateAdvancedSetting(_:value:itemID:)")
        }
        return probes
    }

    // MARK: - Helpers

    private struct PageResult {
        let ids: [String]
        let startIndex: Int
        let total: Int?
    }

    private struct PagedListing {
        let name: String
        /// Folders the listing keeps ahead of the provider's long listing: they are containers, allowed under every
        /// policy.
        let leadingFolders: [String]
        let load: (Int, Int) async throws -> PageResult
    }

    /// Every paged listing of the boundary, each over the provider's long listing.
    private func pagedListings(of fixture: Fixture) -> [PagedListing] {
        let library = fixture.library
        let hub = FakeTitles.hub(id: "listing", items: [])
        return [
            PagedListing(name: "hub items", leadingFolders: []) { start, limit in
                let page = try await fixture.plex.home.items(in: hub, startIndex: start, limit: limit)
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            },
            PagedListing(name: "library items", leadingFolders: []) { start, limit in
                let page = try await fixture.plex.library.items(
                    in: library,
                    parentID: nil,
                    startIndex: start,
                    limit: limit,
                )
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            },
            PagedListing(name: "collection page, no server total", leadingFolders: []) { start, limit in
                let service = try XCTUnwrap(fixture.plex.library as? any PlexAdvancedLibraryService)
                let page = try await service.collectionPage(sectionID: 1, startIndex: start, limit: limit)
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            },
            PagedListing(name: "Jellyfin browse", leadingFolders: []) { start, limit in
                let service = try XCTUnwrap(fixture.jellyfin.library as? any AdvancedLibraryBrowseService)
                let page = try await service.browseItems(
                    in: library,
                    parentID: nil,
                    query: LibraryBrowseQuery(),
                    startIndex: start,
                    limit: limit,
                )
                return PageResult(ids: page.items.map(\.id), startIndex: page.startIndex, total: page.totalCount)
            },
            PagedListing(name: "Plex advanced browse", leadingFolders: ["folder"]) { start, limit in
                let service = try XCTUnwrap(fixture.plex.library as? any PlexAdvancedLibraryService)
                let page = try await service.advancedBrowse(
                    path: "/library/sections/1/all",
                    queryItems: [URLQueryItem(name: "includeMeta", value: start == 0 ? "1" : nil)],
                    startIndex: start,
                    limit: limit,
                )
                // The page carries no start index: it is the one requested.
                return PageResult(ids: page.items.map(\.id), startIndex: start, total: page.totalCount)
            },
        ]
    }

    /// The sample library on a `SessionManager` with stores of its own (a throwaway defaults suite, in-memory
    /// secrets), started through the production bootstrap, `ServerRegistry` and `SafeMediaServices`. Callers stop it.
    private func startIsolatedSampleLibrary() async throws -> (SessionManager, SettingsManager) {
        let suite = "PlinxSafeMediaServicesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(userDefaults: defaults)
        let session = SessionManager(
            settingsManager: settings,
            favoritesStore: FavoritesStore(userDefaults: defaults),
            trackSelectionCoordinator: TrackSelectionCoordinator(
                store: TrackSelectionStore(userDefaults: defaults),
                settingsManager: settings,
            ),
            versionSelectionStore: MediaVersionSelectionStore(userDefaults: defaults),
            accountStore: AccountStore(userDefaults: defaults, secureStore: InMemorySecureStore()),
            profileStore: ProfileStore(userDefaults: defaults),
        )
        var attempts = 0
        while session.status == .hydrating, attempts < 100 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(session.status, .needsAccount, "A session without accounts waits for one")
        await DemoFixtureBootstrap.start(sessionManager: session)
        XCTAssertEqual(session.status, .ready, "The sample library started")
        XCTAssertNotNil(session.registry.services(for: DemoFixtureBootstrap.server))
        return (session, settings)
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
    /// The server management of an administrator, so a locked gate is what keeps every action from it.
    let management = FakeManagement()
    let plex: MediaServices
    let jellyfin: MediaServices
    let library = Library(id: "1", title: "Movies", type: .movie, sectionId: 1, server: FakeTitles.server)

    init() {
        plex = Self.services(
            provider: provider,
            library: FakePlexLibrary(provider: provider),
            management: management,
            gate: gate,
        )
        jellyfin = Self.services(
            provider: provider,
            library: FakeBrowseLibrary(provider: provider),
            management: management,
            gate: gate,
        )
    }

    private static func services(
        provider: FakeProvider,
        library: any MediaLibraryService,
        management: FakeManagement,
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
            management: management,
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

    static func media(
        _ id: String,
        rating: String?,
        type: MediaKind = .movie,
        parent: String? = nil,
        grandparent: String? = nil,
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: "plex://\(id)",
            summary: nil,
            title: id,
            type: type,
            parentRatingKey: parent,
            grandparentRatingKey: grandparent,
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

    static let subtitle = RemoteSubtitleResult(
        id: "subtitle",
        title: "Subtitle",
        language: "en",
        codec: "srt",
        providerTitle: nil,
    )

    static let entry = PlaylistEntry(id: "entry", entryID: "entry", media: .playable(media("allowed", rating: "PG")))
}

/// What the management requests of `FakeManagement` take and return.
private enum ManagementFixture {
    static let artworkOption = ArtworkOption(
        id: "poster",
        previewURL: URL(string: "https://fake-server.test/poster.jpg")!,
        source: "poster",
        provider: nil,
        width: nil,
        height: nil,
        language: nil,
        isSelected: false,
    )

    static let upload = ArtworkUpload(data: Data([0xFF, 0xD8]), contentType: "image/jpeg")

    static let match = MatchCandidate(
        id: "match",
        title: "Match",
        year: nil,
        posterURL: nil,
        provider: nil,
        isCurrent: false,
        payload: .plex(guid: "plex://match"),
    )

    static let draft = MetadataDraft(
        fields: [.title],
        values: [.title: "Title"],
        lists: [:],
        lockedFields: [],
        lockableFields: [.title],
        payload: .plex(sectionID: "1", type: 1),
    )

    static let setting = ItemSetting(id: "episodeSort", label: "Episode sorting", summary: nil, value: "-1", options: [])
}

/// A listing and two policies for tightening the ceiling: every title passes the permissive policy, and only the TV-Y
/// one of every four passes the strict one.
private enum TighteningFixture {
    static let permissive = SafetyPolicy.ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: true)
    static let strict = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)

    static let listing: [MediaItem] = (0 ..< 200).map { index in
        switch index % 4 {
        case 0: FakeTitles.media("tight\(index)-kept", rating: "TV-Y", type: .series)
        case 1: FakeTitles.media("tight\(index)-tvy7", rating: "TV-Y7", type: .series)
        case 2: FakeTitles.media("tight\(index)-tv14", rating: "TV-14", type: .series)
        default: FakeTitles.media("tight\(index)-norating", rating: nil, type: .series)
        }
    }

    static var permittedIDs: [String] {
        listing.map(\.id)
    }

    static var keptIDs: [String] {
        listing.map(\.id).filter { !isDroppedWhenTightened($0) }
    }

    /// Allowed by the permissive policy only.
    static func isDroppedWhenTightened(_ id: String) -> Bool {
        id.hasPrefix("tight") && !id.hasSuffix("-kept")
    }
}

/// Series and their seasons and episodes, rated the way servers rate them: the series, rarely the rest.
private enum SeriesFixture {
    static let mature = FakeTitles.media("show-mature", rating: "TV-MA", type: .series)
    static let kids = FakeTitles.media("show-kids", rating: "TV-Y", type: .series)
    /// Its lookup answers with a movie, which cannot stand for the series.
    static let impostor = FakeTitles.media("show-impostor", rating: "G")

    /// What the provider's own lookup finds. `show-missing` is not there.
    static let catalog = [mature, kids, impostor]

    /// A Plex season: its series is its parent.
    static let season = FakeTitles.media("season-mature-plex", rating: nil, type: .season, parent: "show-mature")

    static let children = [
        episode("ep-mature-unrated", rating: nil, series: "show-mature"),
        episode("ep-mature-blank", rating: " ", series: "show-mature"),
        // Rated within the ceiling, but its series is not.
        episode("ep-mature-rated", rating: "TV-Y", series: "show-mature"),
        season,
        // A Jellyfin season: its series is its grandparent (`SeriesId`).
        FakeTitles.media(
            "season-mature-jellyfin",
            rating: nil,
            type: .season,
            parent: "show-mature",
            grandparent: "show-mature",
        ),
        episode("ep-kids-unrated", rating: nil, series: "show-kids"),
        episode("ep-orphan-unrated", rating: nil, series: "show-missing"),
        episode("ep-orphan-rated", rating: "TV-Y", series: "show-missing"),
        episode("ep-impostor-unrated", rating: nil, series: "show-impostor"),
    ]

    /// An episode as both servers give it: its season as parent, its series as grandparent.
    static func episode(_ id: String, rating: String?, series: String) -> MediaItem {
        FakeTitles.media(id, rating: rating, type: .episode, parent: "\(series)-season", grandparent: series)
    }

    /// Under a TV-PG ceiling: the unrated episode of the TV-Y series, and the TV-Y episode whose series is unknown.
    static let allowedChildIDs = ["ep-kids-unrated", "ep-orphan-rated"]

    static var blockedChildIDs: [String] {
        children.map(\.id).filter { !allowedChildIDs.contains($0) }
    }

    /// The seasons and episodes among `ids`, in their order.
    static func childIDs(in ids: [String]) -> [String] {
        let childIDs = Set(children.map(\.id))
        return ids.filter { childIDs.contains($0) }
    }
}

/// A collection and a playlist carrying the server's composite artwork and counts.
private enum ContainerFixture {
    static let collection = CollectionMediaItem(
        id: "collection",
        key: "collection",
        guid: "plex://collection",
        type: .collection,
        title: "Collection",
        summary: nil,
        thumbPath: "/library/collections/collection/composite/1",
        childCount: 4,
        minYear: nil,
        maxYear: nil,
        server: FakeTitles.server,
    )

    static let playlist = PlaylistMediaItem(
        id: "playlist",
        key: "playlist",
        guid: "plex://playlist",
        type: .playlist,
        title: "Playlist",
        summary: nil,
        compositePath: "/playlists/playlist/composite/1",
        duration: 5_400_000,
        leafCount: 4,
        playlistType: "video",
        server: FakeTitles.server,
    )
}

private enum FakeProviderError: Error {
    case reachedProvider
    case notFound
}

// MARK: - Fake provider

/// Returns the allowed title next to blocked ones from every content method and from its offline caches, and records
/// every parent-only or disabled call that reaches it.
@MainActor
private final class FakeProvider: MediaHomeService, MediaSearchService, MediaArtworkService, MediaDetailService,
    MediaFavoritesService, MediaPlaylistService, MediaPlaybackService, MediaTrackSelectionMemoryService,
    MediaLiveTVService, MediaDownloadService, MediaAuthorizationService, OfflineHomeCacheReading,
    OfflineDetailCacheReading
{
    let allowed = FakeTitles.media("allowed", rating: "PG")
    let overCeiling = FakeTitles.media("over-ceiling", rating: "R")
    let unrated = FakeTitles.media("unrated", rating: nil)
    let adultOnly = FakeTitles.media("adult-only", rating: "NC-17")
    /// A long server listing, so filtered paging needs several server pages.
    var listing: [MediaItem] = (0 ..< 150).map { index in
        switch index % 3 {
        case 0: FakeTitles.media("page\(index)-allowed", rating: "TV-Y7", type: .series)
        case 1: FakeTitles.media("page\(index)-over-ceiling", rating: "TV-14", type: .series)
        default: FakeTitles.media("page\(index)-unrated", rating: "Not Rated", type: .series)
        }
    }

    private(set) var calls: [String] = []
    /// The title the server puts in a playback plan, keyed by the requested ID. Unset, the plan carries the requested
    /// title; set, it stands for a title re-rated on the server since the caller loaded it.
    var preparedMedia: [String: MediaItem] = [:]
    /// Every `mediaItem(id:)` request, the boundary's series lookups included.
    private(set) var lookedUp: [String] = []

    /// Returned after the four titles wherever they are, e.g. seasons and episodes.
    var extraTitles: [MediaItem] = []
    /// Found by `mediaItem(id:)` but listed nowhere, e.g. the series of the extra titles.
    var seriesCatalog: [MediaItem] = []
    /// Returned after the titles by the display listings (search, hub pages, person, recommended hubs).
    var containers: [MediaDisplayItem] = []
    var listedCollections: [CollectionMediaItem] = []
    var listedPlaylists: [PlaylistMediaItem] = []

    var titles: [MediaItem] {
        [allowed, overCeiling, unrated, adultOnly] + extraTitles
    }

    var blockedTitles: [MediaItem] {
        [overCeiling, unrated, adultOnly]
    }

    var displayTitles: [MediaDisplayItem] {
        titles.map(MediaDisplayItem.playable) + containers
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
        lookedUp.append(id)
        if let series = seriesCatalog.first(where: { $0.id == id }) {
            return series
        }
        return try title(id)
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
        return [FakeTitles.subtitle]
    }

    func installSubtitle(itemID _: String, result _: RemoteSubtitleResult) async throws {
        calls.append("installSubtitle")
    }

    func details(for media: MediaItem) async throws -> MediaDetailContent {
        detailContent(for: media)
    }

    /// A blocked series and on-deck title, and every title as seasons, episodes and related hubs.
    private func detailContent(for media: MediaItem) -> MediaDetailContent {
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
        return true
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
        [overCeiling, unrated, allowed, adultOnly] + extraTitles
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
        quality: TranscodeQualityPreset,
        trackPreference _: MediaTrackPreference?,
        version _: MediaVersionRequest,
    ) async throws -> PlaybackPlan {
        calls.append("prepare:\(media.id)")
        return PlaybackPlan(
            media: preparedMedia[media.id] ?? media,
            url: URL(string: "https://fake-server.test/video/\(media.id)")!,
            httpHeaders: [:],
            method: .directPlay,
            requestedQuality: quality,
            effectiveQuality: quality,
            qualityFallbackMessage: nil,
            mediaSourceID: nil,
            playSessionID: "session-\(media.id)",
            transcodeSessionID: nil,
            initialPosition: nil,
            selectedAudioIndex: nil,
            selectedSubtitleIndex: nil,
            subtitleSelectionIsOff: false,
            tracks: [],
            externalSubtitles: [],
            chapters: [],
            skipSegments: [],
            scrubThumbnailSource: nil,
            versions: [],
            versionID: nil,
        )
    }

    func release(plan: PlaybackPlan) async {
        calls.append("release:\(plan.media.id)")
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

    // OfflineHomeCacheReading

    /// The rows the provider's home would show, as last cached: the same mix of allowed and blocked titles and copies.
    func cachedHome() -> HomeContent? {
        HomeContent(rows: rows)
    }

    // OfflineDetailCacheReading

    func cachedDetails(for media: MediaItem) -> MediaDetailContent? {
        detailContent(for: media)
    }

    func canOpenPerson(id _: String) -> Bool {
        true
    }

    func forgetDeletedMedia(itemID: String) {
        calls.append("forgetDeletedMedia:\(itemID)")
    }
}

/// Answers every management request as an administrator's server would, and records each one that reaches it by its
/// selector, property reads included.
@MainActor
private final class FakeManagement: MediaManagementService {
    private(set) var calls: [String] = []

    func received(_ selector: String) -> Bool {
        calls.contains(selector)
    }

    func refreshMetadata(itemID _: String) async throws {
        calls.append("refreshMetadata(itemID:)")
    }

    var supportsAnalyze: Bool {
        calls.append("supportsAnalyze")
        return true
    }

    func analyze(itemID _: String) async throws {
        calls.append("analyze(itemID:)")
    }

    func scanLibrary(id _: String) async throws {
        calls.append("scanLibrary(id:)")
    }

    func refreshLibraryMetadata(id _: String) async throws {
        calls.append("refreshLibraryMetadata(id:)")
    }

    func analyzeLibrary(id _: String) async throws {
        calls.append("analyzeLibrary(id:)")
    }

    var supportsLibraryTrash: Bool {
        calls.append("supportsLibraryTrash")
        return true
    }

    func emptyLibraryTrash(id _: String) async throws {
        calls.append("emptyLibraryTrash(id:)")
    }

    func artworkKinds(for _: MediaItem) -> [EditableArtworkKind] {
        calls.append("artworkKinds(for:)")
        return [.poster]
    }

    func artworkOptions(for _: MediaItem, kind _: EditableArtworkKind) async throws -> [ArtworkOption] {
        calls.append("artworkOptions(for:kind:)")
        return [ManagementFixture.artworkOption]
    }

    func selectArtwork(_: ArtworkOption, for _: MediaItem, kind _: EditableArtworkKind) async throws {
        calls.append("selectArtwork(_:for:kind:)")
    }

    func uploadArtwork(_: ArtworkUpload, for _: MediaItem, kind _: EditableArtworkKind) async throws {
        calls.append("uploadArtwork(_:for:kind:)")
    }

    func deletionImpact(of _: MediaItem) async throws -> MediaDeletionImpact {
        calls.append("deletionImpact(of:)")
        return .files(count: 1, totalSize: nil)
    }

    func delete(_: MediaItem) async throws {
        calls.append("delete(_:)")
    }

    func searchMatches(for _: MediaItem, title _: String, year _: Int?) async throws -> [MatchCandidate] {
        calls.append("searchMatches(for:title:year:)")
        return [ManagementFixture.match]
    }

    func applyMatch(_: MatchCandidate, to _: MediaItem) async throws {
        calls.append("applyMatch(_:to:)")
    }

    var supportsUnmatch: Bool {
        calls.append("supportsUnmatch")
        return true
    }

    func unmatch(itemID _: String) async throws {
        calls.append("unmatch(itemID:)")
    }

    func editableMetadataFields(for _: MediaItem) -> [MetadataField] {
        calls.append("editableMetadataFields(for:)")
        return [.title]
    }

    func loadMetadataDraft(for _: MediaItem) async throws -> MetadataDraft {
        calls.append("loadMetadataDraft(for:)")
        return ManagementFixture.draft
    }

    func saveMetadata(_: MetadataDraft, original _: MetadataDraft, for _: MediaItem) async throws {
        calls.append("saveMetadata(_:original:for:)")
    }

    func metadataSuggestions(for _: MetadataField, item _: MediaItem) async throws -> [String] {
        calls.append("metadataSuggestions(for:item:)")
        return ["Family"]
    }

    func supportsAdvancedSettings(for _: MediaItem) -> Bool {
        calls.append("supportsAdvancedSettings(for:)")
        return true
    }

    func advancedSettings(itemID _: String) async throws -> [ItemSetting] {
        calls.append("advancedSettings(itemID:)")
        return [ManagementFixture.setting]
    }

    func updateAdvancedSetting(_: ItemSetting, value _: String, itemID _: String) async throws {
        calls.append("updateAdvancedSetting(_:value:itemID:)")
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
        provider.listedCollections
    }

    func playlists(in _: Library) async throws -> [PlaylistMediaItem] {
        provider.listedPlaylists
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
    /// Every protocol declared in these files must be reviewed: the provider services, the offline caches their
    /// wrappers expose (`OfflineHomeCacheReading`, `OfflineDetailCacheReading`), and the account preferences
    /// `MediaServices` stores.
    static let allProtocolFiles = [
        "Core/Services/Protocols/MediaServiceProtocols.swift",
        "Core/Services/MediaServices.swift",
        "Core/Safety/SafeContentServices.swift",
        "Core/Services/AccountPreferencesService.swift",
    ]

    /// Where `MediaServices` is declared, for the services it stores.
    static let mediaServicesFile = "Core/Services/MediaServices.swift"

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

    /// The protocols each property of a type is declared as, by property name: `home: ["MediaHomeService"]` for
    /// `let home: any MediaHomeService`, and the same for `(any …)?` and `any A & B`. Only properties declared in the
    /// type's own body count, not parameters, locals, or the properties of nested types.
    static func existentialProperties(of typeName: String, in source: String) -> [String: [String]] {
        let code = strippingComments(source)
        guard let body = body(of: typeName, declaredAs: "(?:class|struct|actor|enum)", in: code) else { return [:] }
        let declarations = outermostText(of: body)
        let property = try! NSRegularExpression(
            pattern: #"\b(?:let|var)[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*:[ \t]*([^=\n{]+)"#,
        )
        let existential = try! NSRegularExpression(
            pattern: #"\bany\s+([A-Za-z_][A-Za-z0-9_.]*(?:\s*&\s*[A-Za-z_][A-Za-z0-9_.]*)*)"#,
        )
        var properties: [String: [String]] = [:]
        for match in property.matches(in: declarations, range: NSRange(declarations.startIndex..., in: declarations)) {
            guard let nameRange = Range(match.range(at: 1), in: declarations),
                  let typeRange = Range(match.range(at: 2), in: declarations)
            else { continue }
            let type = String(declarations[typeRange])
            let protocols = existential.matches(in: type, range: NSRange(type.startIndex..., in: type))
                .compactMap { Range($0.range(at: 1), in: type).map { String(type[$0]) } }
                .flatMap { $0.split(separator: "&").map { $0.trimmingCharacters(in: .whitespaces) } }
            if !protocols.isEmpty {
                properties[String(declarations[nameRange])] = protocols
            }
        }
        return properties
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

    /// The text between the braces of a declaration: a protocol's, unless `keyword` (a pattern) names another kind.
    private static func body(of name: String, declaredAs keyword: String = "protocol", in code: String) -> String? {
        let pattern = #"\b"# + keyword + #"\s+"# + NSRegularExpression.escapedPattern(for: name) + #"\b[^{]*\{"#
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

    /// The text outside every nested pair of braces (function and accessor bodies, nested types), lines kept apart.
    private static func outermostText(of body: String) -> String {
        var text = ""
        var depth = 0
        for character in body {
            switch character {
            case "{": depth += 1
            case "}": depth -= 1
            default:
                if depth == 0 || character == "\n" {
                    text.append(character)
                }
            }
        }
        return text
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
