#if os(tvOS)
import XCTest
import PlinxCore
@testable import Plinx

/// Live parity tests for the Apple TV library grids: what a child sees on the
/// Browse and Collections tabs against an oracle computed from the raw Plex
/// responses and the family policy.
///
/// The app side runs the production path: `PlexMediaServicesFactory` builds the
/// server's `MediaServices`, so every page goes through the `SafeMediaServices`
/// boundary and `ContentSafetyGate.shared`; the tvOS view models page through it
/// and the browse grid's own step (`PlinxLibraryBrowseListing`) runs on top. The
/// oracle reads the same Plex endpoints directly and applies the policy rules on
/// its own.
///
/// Run with `PLINX_PLEX_SERVER_URL` and `PLINX_PLEX_TOKEN` in test_creds.yaml or
/// the test environment; without them every test skips.
@MainActor
final class AppleTVLibraryParityLiveTests: XCTestCase {
    /// Family policy of the parity tests: PG / TV-PG, unrated titles hidden.
    private let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
    private var originalSharedPolicy: SafetyPolicy?
    private var defaultsSuiteNames: [String] = []

    private struct BrowseParityEntry: Equatable, Hashable {
        let kind: String
        let id: String
    }

    private struct LiveServer {
        let context: PlexAPIContext
        let services: MediaServices
    }

    /// The listing request the browse grid sends once the library's sorts and
    /// filters (`meta`) are known.
    private struct BrowseQuery {
        let path: String
        let queryItems: [URLQueryItem]
    }

    override func setUp() async throws {
        try await super.setUp()
        // The provider boundary and the browse grid read the shared gate, so the
        // tests run under the parity policy and restore the app's afterwards.
        originalSharedPolicy = ContentSafetyGate.shared.policy
        ContentSafetyGate.shared.policy = policy
    }

    override func tearDown() async throws {
        if let originalSharedPolicy {
            ContentSafetyGate.shared.policy = originalSharedPolicy
        }
        originalSharedPolicy = nil
        for suiteName in defaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        defaultsSuiteNames = []
        try await super.tearDown()
    }

    // MARK: - Browse

    func test_liveAppleTVBrowseParity_movieLibrary_fullPagination() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .movie, server: server)
        for library in libraries {
            try await assertTVBrowseParity(library: library, server: server, policy: policy)
        }
    }

    func test_liveAppleTVBrowseParity_showLibrary_fullPagination() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickLibraries(type: .series, server: server)
        for library in libraries {
            try await assertTVBrowseParity(library: library, server: server, policy: policy)
        }
    }

    /// Other Videos libraries (None-agent and clip libraries) get no exception
    /// from the family policy: their unrated titles stay hidden unless a parent
    /// allows unrated content.
    func test_liveAppleTVBrowseParity_otherVideoLibrary_hidesUnratedUnderFamilyPolicy() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickOtherVideoLibraries(server: server)

        for library in libraries {
            assertOtherVideoArtworkPolicy(library)
            let shownItems = try await assertTVBrowseParity(library: library, server: server, policy: policy)
            XCTAssertFalse(
                shownItems.contains(where: isUnratedPlayable),
                "Apple TV Other Videos browse must not show unrated titles while unrated content is not allowed. Library: \(library.title)"
            )
        }
    }

    /// With the parent's opt-in, the unrated titles of Other Videos libraries
    /// (home videos, clips) appear, still within the rating ceilings.
    func test_liveAppleTVBrowseParity_otherVideoLibrary_showsUnratedWhenParentAllows() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await pickOtherVideoLibraries(server: server)

        let unratedAllowedPolicy = SafetyPolicy.ratingOnly(
            maxMovie: policy.maxMovieRating,
            maxTV: policy.maxTVRating,
            allowUnrated: true
        )
        ContentSafetyGate.shared.policy = unratedAllowedPolicy

        var sawUnratedPlayable = false
        for library in libraries {
            assertOtherVideoArtworkPolicy(library)
            let shownItems = try await assertTVBrowseParity(
                library: library,
                server: server,
                policy: unratedAllowedPolicy
            )
            sawUnratedPlayable = sawUnratedPlayable || shownItems.contains(where: isUnratedPlayable)
        }

        guard sawUnratedPlayable else {
            throw XCTSkip("No unrated playable item was present in eligible Other Videos libraries at test time.")
        }
    }

    // MARK: - Collections

    func test_liveAppleTVCollectionsParity_initialAndPagedLoads() async throws {
        let server = try await makeLiveServerOrSkip()
        let libraries = try await server.services.library.libraries().filter { $0.sectionId != nil }
        guard !libraries.isEmpty else {
            throw XCTSkip("No eligible libraries available for Apple TV collections parity test.")
        }

        for library in libraries {
            try await assertTVCollectionsParity(library: library, server: server)
        }
    }

    // MARK: - Parity assertions

    /// Loads the browse listing like the Apple TV grid does (first page, then the
    /// next position each time the trailing placeholder appears), compares the
    /// shown run against the oracle, and returns it.
    @discardableResult
    private func assertTVBrowseParity(
        library: Library,
        server: LiveServer,
        policy: SafetyPolicy
    ) async throws -> [LibraryBrowseItem] {
        let settings = makeSettings()
        settings.setDisplayCollections(false)

        let query = try await resolvedBrowseQuery(library: library, server: server, settings: settings)

        let vm = LibraryBrowseViewModel(
            library: library,
            services: server.services,
            settingsManager: settings,
            browseSession: LibraryBrowseSession()
        )
        let listing = await loadTVBrowseListing(vm, library: library)

        XCTAssertNil(vm.errorMessage, "Apple TV browse failed to load. Library: \(library.title)")
        XCTAssertNil(
            listing.nextIndex,
            "Apple TV browse never reached the end of the listing. Library: \(library.title)"
        )
        XCTAssertEqual(
            Array(vm.itemsByIndex.keys.sorted()),
            Array(0..<vm.itemsByIndex.count),
            "Apple TV filtered browse must compact itemsByIndex; sparse indexes stall the grid. Library: \(library.title)"
        )

        let actualEntries = listing.items.map(browseEntry)
        XCTAssertEqual(
            Set(actualEntries).count,
            actualEntries.count,
            "Apple TV browse contains duplicate entries; this causes SwiftUI identity collisions in the grid. Library: \(library.title)"
        )

        let expectedEntries = try await expectedBrowseEntries(
            library: library,
            server: server,
            query: query,
            policy: policy,
            pageSize: 40
        )
        XCTAssertEqual(
            actualEntries,
            expectedEntries,
            "Apple TV browse entries must match Plex+policy oracle across full pagination. Library: \(library.title)"
        )
        XCTAssertTrue(
            listing.items.allSatisfy { item in
                guard case let .media(media) = item else { return true }
                return isShownInBrowse(media, library: library, policy: policy)
            },
            "Apple TV browse items must satisfy the policy oracle. Library: \(library.title)"
        )

        if library.type == .movie || library.type == .series {
            XCTAssertFalse(
                listing.items.contains { item in
                    guard case let .media(media) = item, case .collection = media else { return false }
                    return true
                },
                "Apple TV movie/show browse must exclude collections; they have their own tab. Library: \(library.title)"
            )
        }

        return listing.items
    }

    private func assertOtherVideoArtworkPolicy(
        _ library: Library,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for surface in LibraryCardLayoutPolicy.DetailSurface.allCases {
            XCTAssertTrue(
                LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: surface),
                "Other Videos library detail surfaces must all use landscape cards. Library: \(library.title), surface: \(surface)",
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library),
            .thumb,
            "Other Videos landscape cards must use thumbnails, not poster/backdrop art. Library: \(library.title)",
            file: file,
            line: line
        )
    }

    private func assertTVCollectionsParity(library: Library, server: LiveServer) async throws {
        let settings = makeSettings()
        let vm = LibraryCollectionsViewModel(library: library, services: server.services, settingsManager: settings)

        await vm.load()
        await drainTVCollectionPages(vm)

        let expectedEntries = try await expectedCollectionEntries(
            library: library,
            server: server,
            pageSize: 40
        )
        let actualItems = tvCollectionItems(vm)
        let actualEntries = actualItems.map(mediaEntry)

        XCTAssertNil(vm.errorMessage, "Apple TV collections failed to load. Library: \(library.title)")
        XCTAssertEqual(
            Array(vm.itemsByIndex.keys.sorted()),
            Array(0..<vm.itemsByIndex.count),
            "Apple TV filtered collections must compact itemsByIndex; sparse indexes create blank grid cells. Library: \(library.title)"
        )
        // The collections grid lays out one cell per position up to the total,
        // so a total past the loaded items leaves placeholder cells behind.
        XCTAssertEqual(
            vm.totalItemCount,
            vm.itemsByIndex.count,
            "Apple TV collections total must match the loaded items; extra positions create blank grid cells. Library: \(library.title)"
        )
        XCTAssertEqual(
            actualEntries,
            expectedEntries,
            "Apple TV collections entries must match Plex+policy oracle across full pagination. Library: \(library.title)"
        )
        XCTAssertTrue(
            actualItems.allSatisfy { isAllowedByPolicy($0, policy: policy) },
            "Apple TV collections items must satisfy the policy oracle. Library: \(library.title)"
        )
    }

    // MARK: - Loading

    /// Drives the browse view model the way the Apple TV grid does and returns
    /// the run the grid shows.
    private func loadTVBrowseListing(
        _ vm: LibraryBrowseViewModel,
        library: Library
    ) async -> PlinxLibraryBrowseListing {
        await vm.load()
        var listing = PlinxLibraryBrowseListing(
            itemsByIndex: vm.itemsByIndex,
            totalItemCount: vm.totalItemCount,
            library: library
        )

        // Stop when there is no growth for several attempts to avoid infinite loops.
        let maxSteps = 300
        var steps = 0
        var stagnantSteps = 0
        while let nextIndex = listing.nextIndex, steps < maxSteps, stagnantSteps < 3 {
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

    private func drainTVCollectionPages(_ vm: LibraryCollectionsViewModel) async {
        var stagnantAttempts = 0
        var previousCount = vm.itemsByIndex.count
        let maxAttempts = 300

        for _ in 0..<maxAttempts {
            await vm.loadPagesAround(index: max(vm.totalItemCount - 1, 0))
            let currentCount = vm.itemsByIndex.count
            if currentCount == previousCount {
                stagnantAttempts += 1
            } else {
                stagnantAttempts = 0
                previousCount = currentCount
            }
            if stagnantAttempts >= 3 {
                break
            }
        }
    }

    private func tvCollectionItems(_ vm: LibraryCollectionsViewModel) -> [MediaDisplayItem] {
        vm.itemsByIndex.keys.sorted().compactMap { vm.itemsByIndex[$0] }
    }

    // MARK: - Live server

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
        let suiteName = "AppleTVLibraryParityLiveTests.\(UUID().uuidString)"
        defaultsSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Settings apart from the app's, so saved browse selections cannot leak
    /// between runs.
    private func makeSettings() -> SettingsManager {
        SettingsManager(userDefaults: makeDefaults())
    }

    private func pickLibraries(type: MediaKind, server: LiveServer) async throws -> [Library] {
        let candidates = try await server.services.library.libraries().filter {
            $0.type == type && !$0.isNoneAgentLibrary && $0.sectionId != nil
        }

        guard !candidates.isEmpty else {
            throw XCTSkip("No eligible \(type.rawValue) library available for live Apple TV parity test.")
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
            throw XCTSkip("No eligible Other Videos-style library available for live Apple TV parity test.")
        }
        return candidates
    }

    private func sectionId(for library: Library) throws -> Int {
        guard let sectionId = library.sectionId else {
            throw XCTSkip("Library \(library.title) is missing sectionId.")
        }
        return sectionId
    }

    // MARK: - Oracle

    /// The request the browse grid sends after its first page: the display type
    /// and sort confirmed by the library's `meta`.
    private func resolvedBrowseQuery(
        library: Library,
        server: LiveServer,
        settings: SettingsManager
    ) async throws -> BrowseQuery {
        guard let browsePath = library.plexBrowsePath else {
            throw XCTSkip("Library \(library.title) has no browse path.")
        }
        let includeCollections: Bool? = settings.interface.displayCollections ? true : nil
        let defaultEndpoint = PlexEndpoint(
            path: browsePath,
            queryItems: [URLQueryItem(name: "type", value: defaultBrowseTypeQueryValue(for: library))]
        )

        let controls = LibraryBrowseControlsViewModel(advancedService: nil, library: library)
        let response = try await SectionRepository(context: server.context).getSectionBrowseItems(
            path: defaultEndpoint.path,
            queryItems: controls.buildQueryItems(
                baseItems: defaultEndpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: true
            ),
            pagination: PlexPagination(start: 0, size: 1)
        )
        if let meta = response.mediaContainer.meta {
            controls.applyMeta(meta)
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

    /// The raw Plex listing for `query`, with the policy and the browse grid's
    /// own rule (collections of movie and TV libraries have their own tab)
    /// applied independently of the app.
    private func expectedBrowseEntries(
        library: Library,
        server: LiveServer,
        query: BrowseQuery,
        policy: SafetyPolicy,
        pageSize: Int
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
                    entries.append(mediaEntry(displayItem))
                }
            }

            let total = response.mediaContainer.totalSize ?? (start + metadata.count)
            start += metadata.count
            if start >= total {
                break
            }
        }

        return entries
    }

    private func expectedCollectionEntries(
        library: Library,
        server: LiveServer,
        pageSize: Int
    ) async throws -> [BrowseParityEntry] {
        let sectionRepository = try SectionRepository(context: server.context)
        let sectionId = try sectionId(for: library)
        var entries: [BrowseParityEntry] = []
        var start = 0
        let maxPages = 300

        for _ in 0..<maxPages {
            let response = try await sectionRepository.getSectionCollections(
                sectionId: sectionId,
                includeCollections: true,
                pagination: PlexPagination(start: start, size: pageSize)
            )
            let metadata = response.mediaContainer.metadata ?? []
            if metadata.isEmpty {
                break
            }

            let pageEntries = metadata.compactMap { plexItem -> BrowseParityEntry? in
                guard let displayItem = MediaDisplayItem(plexItem: plexItem, server: server.services.identity),
                      isAllowedByPolicy(displayItem, policy: policy) else {
                    return nil
                }
                return mediaEntry(displayItem)
            }
            entries.append(contentsOf: pageEntries)

            let total = response.mediaContainer.totalSize ?? (start + metadata.count)
            start += metadata.count
            if start >= total {
                break
            }
        }

        return entries
    }

    /// The browse grid's default listing type before `meta` is known.
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
            return mediaEntry(media)
        }
    }

    private func mediaEntry(_ item: MediaDisplayItem) -> BrowseParityEntry {
        switch item {
        case .collection:
            return BrowseParityEntry(kind: "collection", id: item.id)
        case .playlist:
            return BrowseParityEntry(kind: "playlist", id: item.id)
        case .playable:
            return BrowseParityEntry(kind: "media", id: item.id)
        }
    }

    private func isUnratedPlayable(_ item: LibraryBrowseItem) -> Bool {
        guard case let .media(.playable(media)) = item else { return false }
        return ContentRatingNormalizer.classify(media.contentRating) == .unrated
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
#endif
