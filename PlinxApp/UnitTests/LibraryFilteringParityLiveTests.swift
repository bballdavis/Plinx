import XCTest
import PlinxCore
@testable import Plinx

/// Live parity tests: what a child sees on the library screens against an oracle
/// computed from the raw Plex responses and the family policy.
///
/// The app side runs the production path: `PlexMediaServicesFactory` builds the
/// server's `MediaServices`, so every listing goes through the `SafeMediaServices`
/// boundary and `ContentSafetyGate.shared`; the screens' own Plinx steps
/// (`PlinxLibraryRecommendationLoader`, `PlinxLibraryBrowseListing`,
/// `LibraryCatalogLoader`) run on top. The oracle reads the same Plex endpoints
/// directly and applies the policy rules on its own.
///
/// Run via `./scripts/tests/live_library_parity_tests.sh`, or manually with
/// `PLINX_PLEX_SERVER_URL` and `PLINX_PLEX_TOKEN` in the test environment.
@MainActor
final class LibraryFilteringParityLiveTests: XCTestCase {

    /// Family policy of the parity tests: PG / TV-PG, unrated titles hidden.
    private let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
    private var originalSharedPolicy: SafetyPolicy?
    private var settingsSuiteNames: [String] = []

    private struct BrowseParityEntry: Equatable, Hashable {
        let kind: String
        let id: String
    }

    private struct LiveServer {
        let context: PlexAPIContext
        let services: MediaServices
    }

    /// The listing request the browse screen sends once the library's sorts and
    /// filters (`meta`) are known.
    private struct BrowseQuery {
        let path: String
        let queryItems: [URLQueryItem]
    }

    /// Sort the browse screen starts with: the library's own default, or a saved
    /// "newest first" selection (what the screen restores after a child picked it).
    private enum BrowseSort {
        case libraryDefault
        case newest

        var savedSelection: LibraryBrowsePreferences.PlexSelection? {
            switch self {
            case .libraryDefault:
                return nil
            case .newest:
                return LibraryBrowsePreferences.PlexSelection(
                    sortKey: "addedAt",
                    sortDirection: .desc,
                    sortQueryValue: "addedAt:desc"
                )
            }
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        // The provider boundary and the Plinx screens read the shared gate, so
        // the tests run under the parity policy and restore the app's afterwards.
        originalSharedPolicy = ContentSafetyGate.shared.policy
        ContentSafetyGate.shared.policy = policy
    }

    override func tearDown() async throws {
        if let originalSharedPolicy {
            ContentSafetyGate.shared.policy = originalSharedPolicy
        }
        originalSharedPolicy = nil
        for suiteName in settingsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        settingsSuiteNames = []
        try await super.tearDown()
    }

    // MARK: - Recommended

    func test_liveRecommendedFilteringParity_movieLibrary() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .movie, server: server)
        for library in libraries {
            try await assertRecommendedParity(library: library, server: server)
        }
    }

    func test_liveRecommendedFilteringParity_showLibrary() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .series, server: server)
        for library in libraries {
            try await assertRecommendedParity(library: library, server: server)
        }
    }

    // MARK: - Browse

    func test_liveBrowseFilteringParity_movieLibrary() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .movie, server: server)
        for library in libraries {
            try await assertBrowseParity(library: library, server: server, policy: policy, loadMoreSteps: 1)
        }
    }

    func test_liveBrowseFilteringParity_showLibrary() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .series, server: server)
        for library in libraries {
            try await assertBrowseParity(library: library, server: server, policy: policy, loadMoreSteps: 1)
        }
    }

    func test_liveBrowseFilteringParity_movieLibrary_fullPagination() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .movie, server: server)
        for library in libraries {
            try await assertFullBrowseParity(library: library, server: server, policy: policy, sort: .libraryDefault)
            try await assertFullBrowseParity(library: library, server: server, policy: policy, sort: .newest)
        }
    }

    func test_liveBrowseFilteringParity_showLibrary_fullPagination() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .series, server: server)
        for library in libraries {
            try await assertFullBrowseParity(library: library, server: server, policy: policy, sort: .libraryDefault)
            try await assertFullBrowseParity(library: library, server: server, policy: policy, sort: .newest)
        }
    }

    func test_liveBrowseFilteringParity_otherVideoLibrary_fullPagination() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickOtherVideoLibraries(server: server)
        for library in libraries {
            try await assertFullBrowseParity(library: library, server: server, policy: policy, sort: .libraryDefault)
            try await assertFullBrowseParity(library: library, server: server, policy: policy, sort: .newest)
        }
    }

    /// The gate cannot be switched off, so completeness is checked under the most
    /// permissive policy a parent can choose: every title but adult-only ones.
    func test_liveBrowseCompleteness_otherVideoLibrary_permissivePolicy() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickOtherVideoLibraries(server: server)

        let permissivePolicy = SafetyPolicy.ratingOnly(maxMovie: .r, maxTV: .tvMa, allowUnrated: true)
        ContentSafetyGate.shared.policy = permissivePolicy

        let prioritized = libraries.sorted { lhs, rhs in
            let lhsIsYouTube = lhs.title.lowercased().contains("youtube")
            let rhsIsYouTube = rhs.title.lowercased().contains("youtube")
            if lhsIsYouTube == rhsIsYouTube {
                return lhs.title < rhs.title
            }
            return lhsIsYouTube && !rhsIsYouTube
        }

        for library in prioritized {
            try await assertFullBrowseParity(
                library: library,
                server: server,
                policy: permissivePolicy,
                sort: .libraryDefault,
                oraclePageSize: 200
            )
        }
    }

    // MARK: - Home recently added

    func test_liveHomeRecentlyAdded_otherVideoHubVisibleUnderStrictPolicy() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await server.services.library.libraries()

        let eligibleLibraries = libraries.filter {
            $0.sectionId != nil && HomeLibraryGrouping.isOtherVideo($0)
        }
        guard let library = eligibleLibraries.first(where: {
            $0.title.localizedCaseInsensitiveContains("youtube")
        }) ?? eligibleLibraries.first else {
            throw XCTSkip("No eligible Other Videos-style library available for live home recently-added test.")
        }

        let broadRatedPolicy = SafetyPolicy.ratingOnly(
            maxMovie: .r,
            maxTV: .tvMa,
            allowUnrated: false
        )
        ContentSafetyGate.shared.policy = broadRatedPolicy

        let result = try await LibraryCatalogLoader(services: server.services).recentItems(
            for: library,
            limit: 20
        )
        XCTAssertFalse(
            result.items.isEmpty,
            "The canonical newest-items endpoint returned no rated Other Video items for \(library.title)."
        )
        XCTAssertTrue(
            result.items.allSatisfy { isAllowedByPolicy($0, policy: broadRatedPolicy) },
            "Recently added items must satisfy the policy oracle"
        )

        let rows = HomeRecentlyAddedProjection.rows(
            from: [result],
            combineMoviesTV: true
        )
        XCTAssertEqual(rows.map(\.sectionKey), ["otherVideos"])
        XCTAssertEqual(rows.first?.items.map(\.id), result.items.map(\.id))
        XCTAssertEqual(rows.first?.layout, HomeRecentlyAddedProjection.Layout.landscape)
    }

    // MARK: - Parity assertions

    private func assertRecommendedParity(library: Library, server: LiveServer) async throws {
        let response = try await HubRepository(context: server.context)
            .getSectionHubs(sectionId: try sectionId(for: library))
        let rawHubs = (response.mediaContainer.hub ?? []).map { plexHub in
            Hub(plexHub: plexHub, server: server.services.identity)
        }
        let expectedHubs = expectedRecommendedHubs(from: rawHubs)

        let settings = makeSettings()
        let vm = LibraryRecommendedViewModel(library: library, services: server.services, settingsManager: settings)
        await PlinxLibraryRecommendationLoader.load(
            viewModel: vm,
            services: server.services,
            settingsManager: settings
        )

        XCTAssertNil(vm.errorMessage, "Recommended failed to load for \(library.title)")

        // The discovery row is Plinx's own fallback, drawn from recently added titles.
        let discoveryHubID = LibraryRecommendationFallbackPolicy.discoveryHubID
        let providerHubs = vm.hubs.filter { $0.id != discoveryHubID }

        XCTAssertEqual(
            providerHubs.map(\.id),
            expectedHubs.map(\.id),
            "Recommended hub order/identity must match Plex+policy oracle"
        )
        XCTAssertEqual(providerHubs.count, expectedHubs.count, "Recommended hub counts must match")

        for (actualHub, expectedHub) in zip(providerHubs, expectedHubs) {
            XCTAssertEqual(
                actualHub.items.map(\.id),
                expectedHub.items.map(\.id),
                "Recommended hub item order/identity mismatch for hub \(actualHub.id)"
            )
        }

        if vm.hubs.contains(where: { $0.id == discoveryHubID }) {
            XCTAssertTrue(
                LibraryRecommendationFallbackPolicy.needsDiscoveryHub(expectedHubs),
                "The discovery row is only added when no browsable hub survives the policy"
            )
        }

        XCTAssertTrue(
            vm.hubs.allSatisfy { hub in hub.items.allSatisfy { isAllowedByPolicy($0, policy: policy) } },
            "Every recommended item, discovery row included, must satisfy the policy oracle"
        )
    }

    private func assertFullBrowseParity(
        library: Library,
        server: LiveServer,
        policy: SafetyPolicy,
        sort: BrowseSort,
        oraclePageSize: Int = 100
    ) async throws {
        try await assertBrowseParity(
            library: library,
            server: server,
            policy: policy,
            sort: sort,
            loadMoreSteps: 300,
            requiresCompleteListing: true,
            oraclePageSize: oraclePageSize
        )
    }

    /// Loads the browse listing like the grid does (first page, then the next
    /// position each time the trailing placeholder appears) and compares the
    /// shown run against the oracle.
    private func assertBrowseParity(
        library: Library,
        server: LiveServer,
        policy: SafetyPolicy,
        sort: BrowseSort = .libraryDefault,
        loadMoreSteps: Int,
        requiresCompleteListing: Bool = false,
        oraclePageSize: Int = 100
    ) async throws {
        let settings = makeSettings()
        settings.setDisplayCollections(false)

        guard let query = try await resolvedBrowseQuery(
            library: library,
            server: server,
            settings: settings,
            sort: sort
        ) else {
            // The library does not offer the saved sort; the screen would drop it.
            return
        }

        if let selection = sort.savedSelection {
            let key = LibraryBrowsePreferences.key(
                scopeID: server.services.serverPreferencesScopeID,
                libraryID: library.id
            )
            var preferences = settings.libraryBrowsePreferences(for: key)
            preferences.plex = selection
            settings.setLibraryBrowsePreferences(preferences, for: key)
        }

        let vm = LibraryBrowseViewModel(
            library: library,
            services: server.services,
            settingsManager: settings,
            browseSession: LibraryBrowseSession()
        )
        let listing = await loadBrowseListing(vm, library: library, loadMoreSteps: loadMoreSteps)

        XCTAssertNil(vm.errorMessage, "Browse failed to load for \(library.title)")
        if requiresCompleteListing {
            XCTAssertNil(
                listing.nextIndex,
                "Browse never reached the end of the listing for \(library.title)"
            )
        }

        let actualEntries = listing.items.map(browseEntry)
        XCTAssertEqual(
            Set(actualEntries).count,
            actualEntries.count,
            "Browse results contain duplicate entries; this causes SwiftUI identity collisions in grids/carousels."
        )

        let isComplete = listing.nextIndex == nil
        let expectedEntries = try await expectedBrowseEntries(
            library: library,
            server: server,
            query: query,
            policy: policy,
            pageSize: oraclePageSize,
            minimumCount: isComplete ? nil : actualEntries.count
        )

        if isComplete {
            XCTAssertEqual(
                actualEntries,
                expectedEntries,
                "Browse entries must match Plex+policy oracle across full pagination (including order) for \(library.title)"
            )
        } else {
            XCTAssertEqual(
                actualEntries,
                Array(expectedEntries.prefix(actualEntries.count)),
                "Browse entries must match Plex+policy oracle across the loaded pages (including order) for \(library.title)"
            )
        }

        XCTAssertTrue(listing.items.allSatisfy { item in
            guard case let .media(media) = item else { return true }
            return isShownInBrowse(media, library: library, policy: policy)
        }, "All browse media items must satisfy the policy oracle")
    }

    // MARK: - Helpers

    private func makeLiveServerOrSkip() async throws -> LiveServer {
        let serverRaw = LiveTestCredentials.value(named: "PLINX_PLEX_SERVER_URL")
        let token = LiveTestCredentials.value(named: "PLINX_PLEX_TOKEN")

        guard let serverRaw, !serverRaw.isEmpty,
              let token, !token.isEmpty else {
            throw XCTSkip("Live Plex credentials are not configured. Populate test_creds.yaml with PLINX_PLEX_SERVER_URL and PLINX_PLEX_TOKEN.")
        }

        guard let serverURL = URL(string: serverRaw),
              let host = serverURL.host,
              let scheme = serverURL.scheme else {
            XCTFail("PLINX_PLEX_SERVER_URL is not a valid absolute URL")
            throw XCTSkip("Cannot run live parity tests with invalid server URL.")
        }

        let context = PlexAPIContext()
        await context.waitForBootstrap()
        context.setAuthToken(token)

        let connection = PlexCloudResource.Connection(
            scheme: scheme,
            address: host,
            port: serverURL.port ?? (scheme.lowercased() == "https" ? 443 : 80),
            uri: serverURL,
            isLocal: true,
            isRelay: false,
            isIPv6: host.contains(":")
        )

        let resource = PlexCloudResource(
            name: "Plinx Live Test",
            clientIdentifier: "plinx-live-tests",
            accessToken: token,
            connections: [connection]
        )

        do {
            try await context.selectServer(resource)
        } catch {
            throw XCTSkip("Failed to connect to the configured Plex server for live parity tests.")
        }

        guard let services = PlexMediaServicesFactory.make(
            context: context,
            serverName: resource.name,
            userID: "plinx-live-tests",
            isServerAdministrator: false,
            favoritesProfileID: "plinx-live-tests",
            favoritesStore: FavoritesStore(userDefaults: makeDefaults()),
            trackSelectionCoordinator: nil,
            versionSelectionStore: nil
        ) else {
            throw XCTSkip("The configured Plex server has no usable connection for live parity tests.")
        }

        return LiveServer(context: context, services: services)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LibraryFilteringParityLiveTests.\(UUID().uuidString)"
        settingsSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Settings apart from the app's, so saved browse selections and hidden
    /// sections cannot leak between runs.
    private func makeSettings() -> SettingsManager {
        SettingsManager(userDefaults: makeDefaults())
    }

    private func pickLibraries(type: MediaKind, server: LiveServer) async throws -> [Library] {
        let candidates = try await server.services.library.libraries().filter {
            $0.type == type && !$0.isNoneAgentLibrary && $0.sectionId != nil
        }

        guard !candidates.isEmpty else {
            throw XCTSkip("No eligible \(type.rawValue) library available for live parity test.")
        }
        return candidates
    }

    private func pickOtherVideoLibraries(server: LiveServer) async throws -> [Library] {
        let candidates = try await server.services.library.libraries().filter {
            $0.sectionId != nil && (
                $0.isNoneAgentLibrary || ($0.type != .movie && $0.type != .series)
            )
        }

        guard !candidates.isEmpty else {
            throw XCTSkip("No eligible Other Videos-style library available for live parity test.")
        }
        return candidates
    }

    private func sectionId(for library: Library) throws -> Int {
        guard let sectionId = library.sectionId else {
            throw XCTSkip("Library \(library.title) is missing sectionId.")
        }
        return sectionId
    }

    /// Hubs as the boundary should publish them: blocked titles dropped, hubs
    /// emptied by the policy removed (a hub the server sent empty stays), and
    /// each hub once.
    private func expectedRecommendedHubs(from rawHubs: [Hub]) -> [Hub] {
        var seenIDs = Set<String>()
        return rawHubs.compactMap { hub -> Hub? in
            guard seenIDs.insert(hub.id).inserted else { return nil }
            guard hub.hasItems else { return hub }
            let allowedItems = hub.items.filter { isAllowedByPolicy($0, policy: policy) }
            guard !allowedItems.isEmpty else { return nil }
            return Hub(id: hub.id, title: hub.title, items: allowedItems)
        }
    }

    /// Drives the browse view model the way the grid does and returns the run
    /// the grid shows.
    private func loadBrowseListing(
        _ vm: LibraryBrowseViewModel,
        library: Library,
        loadMoreSteps: Int
    ) async -> PlinxLibraryBrowseListing {
        await vm.load()
        var listing = PlinxLibraryBrowseListing(
            itemsByIndex: vm.itemsByIndex,
            totalItemCount: vm.totalItemCount,
            library: library
        )

        // Stop when there is no growth for several attempts to avoid infinite loops.
        var steps = 0
        var stagnantSteps = 0
        while let nextIndex = listing.nextIndex, steps < loadMoreSteps, stagnantSteps < 3 {
            steps += 1
            // The same request the grid's trailing placeholder makes when it appears.
            await vm.loadPagesAround(index: nextIndex)
            let updated = PlinxLibraryBrowseListing(
                itemsByIndex: vm.itemsByIndex,
                totalItemCount: vm.totalItemCount,
                library: library
            )
            if updated.nextIndex == nextIndex, updated.items.count == listing.items.count {
                stagnantSteps += 1
            } else {
                stagnantSteps = 0
            }
            listing = updated
        }
        return listing
    }

    /// The request the browse screen sends after its first page: the display
    /// type and sort confirmed by the library's `meta`. `nil` when the saved
    /// sort is not offered by the library.
    private func resolvedBrowseQuery(
        library: Library,
        server: LiveServer,
        settings: SettingsManager,
        sort: BrowseSort
    ) async throws -> BrowseQuery? {
        guard let browsePath = library.plexBrowsePath else {
            throw XCTSkip("Library \(library.title) has no browse path.")
        }
        let includeCollections: Bool? = settings.interface.displayCollections ? true : nil
        let defaultEndpoint = PlexEndpoint(
            path: browsePath,
            queryItems: [URLQueryItem(name: "type", value: defaultBrowseTypeQueryValue(for: library))]
        )

        let controls = LibraryBrowseControlsViewModel(
            advancedService: nil,
            library: library,
            pendingRestore: sort.savedSelection
        )
        let response = try await SectionRepository(context: server.context).getSectionBrowseItems(
            path: defaultEndpoint.path,
            queryItems: controls.buildQueryItems(
                baseItems: defaultEndpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: true
            ),
            pagination: PlexPagination(start: 0, size: 1)
        )
        if let meta = response.mediaContainer.meta, controls.applyMeta(meta) {
            return nil
        }

        let endpoint = controls.requestedDisplayTypeKey.flatMap(PlexEndpoint.init(key:)) ?? defaultEndpoint
        return BrowseQuery(
            path: endpoint.path,
            queryItems: controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: false
            )
        )
    }

    /// The raw Plex listing for `query`, with the policy and the browse screen's
    /// own rule (collections of movie and TV libraries have their own tab)
    /// applied independently of the app.
    private func expectedBrowseEntries(
        library: Library,
        server: LiveServer,
        query: BrowseQuery,
        policy: SafetyPolicy,
        pageSize: Int,
        minimumCount: Int?
    ) async throws -> [BrowseParityEntry] {
        let sectionRepository = try SectionRepository(context: server.context)
        var entries: [BrowseParityEntry] = []
        var start = 0
        let maxPages = 300

        for _ in 0..<maxPages {
            let response = try await sectionRepository.getSectionBrowseItems(
                path: query.path,
                queryItems: query.queryItems,
                pagination: PlexPagination(start: start, size: pageSize)
            )
            let metadata = response.mediaContainer.metadata ?? []
            if metadata.isEmpty {
                break
            }

            for entry in metadata {
                switch entry {
                case let .folder(folder):
                    entries.append(BrowseParityEntry(kind: "folder", id: folder.key))
                case let .item(plexItem):
                    guard let displayItem = MediaDisplayItem(plexItem: plexItem, server: server.services.identity),
                          isShownInBrowse(displayItem, library: library, policy: policy)
                    else { continue }
                    entries.append(BrowseParityEntry(kind: "media", id: displayItem.id))
                }
            }

            if let minimumCount, entries.count >= minimumCount {
                break
            }
            let total = response.mediaContainer.totalSize ?? (start + metadata.count)
            start += metadata.count
            if start >= total {
                break
            }
        }

        return entries
    }

    /// The browse screen's default listing type before `meta` is known.
    private func defaultBrowseTypeQueryValue(for library: Library) -> String {
        if library.isShared {
            return PlexSharedLibrary.videoTypes
        }
        switch library.type {
        case .movie:
            return "1"
        case .series:
            return "2"
        default:
            return "1,2"
        }
    }

    private func browseEntry(_ item: LibraryBrowseItem) -> BrowseParityEntry {
        switch item {
        case let .folder(folder):
            return BrowseParityEntry(kind: "folder", id: folder.key)
        case let .media(media):
            return BrowseParityEntry(kind: "media", id: media.id)
        }
    }

    private func isShownInBrowse(_ item: MediaDisplayItem, library: Library, policy: SafetyPolicy) -> Bool {
        if case .collection = item, library.type == .movie || library.type == .series {
            return false
        }
        return isAllowedByPolicy(item, policy: policy)
    }

    /// Policy oracle: collections and playlists are containers; a title is
    /// judged on its own rating, adult-only ratings are always rejected, and
    /// unrated titles pass only when the policy allows them. The family policy
    /// applies to every library alike, None-agent (Other Videos) libraries included.
    private func isAllowedByPolicy(_ item: MediaDisplayItem, policy: SafetyPolicy) -> Bool {
        switch item {
        case .collection, .playlist:
            return true
        case let .playable(media):
            return isAllowedByPolicyRating(media.contentRating, policy: policy)
        }
    }

    private func isAllowedByPolicyRating(_ contentRating: String?, policy: SafetyPolicy) -> Bool {
        switch ContentRatingNormalizer.classify(contentRating) {
        case .adultOnly:
            return false
        case .unrated:
            return policy.allowUnrated
        case let .rated(rating):
            if rating.isTVRating {
                return rating <= policy.maxTVRating
            }
            return rating <= policy.maxMovieRating
        }
    }
}
