#if os(tvOS)
import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class AppleTVLibraryParityLiveTests: XCTestCase {
    private let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)

    private struct BrowseParityEntry: Equatable, Hashable {
        let kind: String
        let id: String
    }

    func test_liveAppleTVBrowseParity_movieLibrary_fullPagination() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .movie, context: context)
        for library in libraries {
            try await assertTVBrowseParity(library: library, context: context)
        }
    }

    func test_liveAppleTVBrowseParity_showLibrary_fullPagination() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .show, context: context)
        for library in libraries {
            try await assertTVBrowseParity(library: library, context: context)
        }
    }

    func test_liveAppleTVBrowseParity_otherVideoLibrary_allowsUnratedNoneAgent() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickOtherVideoLibraries(context: context)
        var sawUnratedPlayable = false

        for library in libraries {
            assertOtherVideoArtworkPolicy(library)
            let containsUnratedPlayable = try await assertTVBrowseParity(library: library, context: context)
            sawUnratedPlayable = sawUnratedPlayable || containsUnratedPlayable
        }

        guard sawUnratedPlayable else {
            throw XCTSkip("No unrated playable item was present in eligible Other Videos libraries at test time.")
        }
    }

    func test_liveAppleTVCollectionsParity_initialAndPagedLoads() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraryStore = LibraryStore(context: context)
        try await libraryStore.loadLibraries()

        let libraries = libraryStore.libraries.filter { $0.sectionId != nil }
        guard !libraries.isEmpty else {
            throw XCTSkip("No eligible libraries available for Apple TV collections parity test.")
        }

        for library in libraries {
            try await assertTVCollectionsParity(library: library, context: context)
        }
    }

    @discardableResult
    private func assertTVBrowseParity(
        library: Library,
        context: PlexAPIContext
    ) async throws -> Bool {
        let settings = SettingsManager()
        settings.setDisplayCollections(false)

        let vm = LibraryBrowseViewModel(library: library, context: context, settingsManager: settings)
        let effectivePolicy = effectivePolicyFor(library)
        vm.itemFilter = { [policy = effectivePolicy] item in
            if HomeLibraryGrouping.isMoviesOrTV(library), case .collection = item {
                return false
            }
            return StrimrAdapter.isAllowed(item, policy: policy)
        }

        await vm.load()
        await drainTVBrowsePages(vm)

        let expectedEntries = try await expectedBrowseEntries(
            library: library,
            context: context,
            includeCollections: HomeLibraryGrouping.isMoviesOrTV(library) ? false : nil,
            pageSize: 40
        )
        let actualEntries = tvBrowseItems(vm).map(browseEntry)

        XCTAssertEqual(
            Array(vm.itemsByIndex.keys.sorted()),
            Array(0..<vm.itemsByIndex.count),
            "Apple TV filtered browse must compact itemsByIndex; sparse indexes create blank grid cells. Library: \(library.title)"
        )
        XCTAssertEqual(
            actualEntries,
            expectedEntries,
            "Apple TV browse entries must match Plex+policy oracle across full pagination. Library: \(library.title)"
        )
        XCTAssertTrue(
            tvBrowseItems(vm).allSatisfy { item in
                guard case let .media(media) = item else { return true }
                return isAllowedByPolicyInLibraryContext(media, library: library)
            },
            "Apple TV browse items must satisfy library-context safety policy. Library: \(library.title)"
        )

        if HomeLibraryGrouping.isMoviesOrTV(library) {
            XCTAssertFalse(
                tvBrowseItems(vm).contains { item in
                    guard case let .media(media) = item, case .collection = media else { return false }
                    return true
                },
                "Apple TV movie/show browse must exclude collections by default. Library: \(library.title)"
            )
        }

        let containsUnratedPlayable = tvBrowseItems(vm).contains { item in
            guard case let .media(.playable(media)) = item else { return false }
            return media.contentRating?.isEmpty ?? true
        }
        return containsUnratedPlayable
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

    private func assertTVCollectionsParity(library: Library, context: PlexAPIContext) async throws {
        let settings = SettingsManager()
        let vm = LibraryCollectionsViewModel(library: library, context: context, settingsManager: settings)
        let effectivePolicy = effectivePolicyFor(library)
        vm.itemFilter = { [policy = effectivePolicy] item in
            StrimrAdapter.isAllowed(item, policy: policy)
        }

        await vm.load()
        await drainTVCollectionPages(vm)

        let expectedEntries = try await expectedCollectionEntries(
            library: library,
            context: context,
            pageSize: 40
        )
        let actualItems = tvCollectionItems(vm)
        let actualEntries = actualItems.map(mediaEntry)

        XCTAssertEqual(
            Array(vm.itemsByIndex.keys.sorted()),
            Array(0..<vm.itemsByIndex.count),
            "Apple TV filtered collections must compact itemsByIndex; sparse indexes create blank grid cells. Library: \(library.title)"
        )
        XCTAssertEqual(
            actualEntries,
            expectedEntries,
            "Apple TV collections entries must match Plex+policy oracle across full pagination. Library: \(library.title)"
        )
        XCTAssertTrue(
            actualItems.allSatisfy { StrimrAdapter.isAllowed($0, policy: effectivePolicy) },
            "Apple TV collections items must satisfy safety policy. Library: \(library.title)"
        )
    }

    private func drainTVBrowsePages(_ vm: LibraryBrowseViewModel) async {
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

    private func tvBrowseItems(_ vm: LibraryBrowseViewModel) -> [LibraryBrowseItem] {
        vm.itemsByIndex.keys.sorted().compactMap { vm.itemsByIndex[$0] }
    }

    private func tvCollectionItems(_ vm: LibraryCollectionsViewModel) -> [MediaDisplayItem] {
        vm.itemsByIndex.keys.sorted().compactMap { vm.itemsByIndex[$0] }
    }

    private func makeLiveContextOrSkip() async throws -> PlexAPIContext {
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

        return context
    }

    private func pickLibraries(type: PlexItemType, context: PlexAPIContext) async throws -> [Library] {
        let libraryStore = LibraryStore(context: context)
        try await libraryStore.loadLibraries()

        let candidates = libraryStore.libraries.filter {
            $0.type == type && !$0.isNoneAgentLibrary && $0.sectionId != nil
        }

        guard !candidates.isEmpty else {
            throw XCTSkip("No eligible \(type.rawValue) library available for live Apple TV parity test.")
        }
        return candidates
    }

    private func pickOtherVideoLibraries(context: PlexAPIContext) async throws -> [Library] {
        let libraryStore = LibraryStore(context: context)
        try await libraryStore.loadLibraries()

        let candidates = libraryStore.libraries.filter {
            $0.sectionId != nil && (
                $0.isNoneAgentLibrary || ($0.type != .movie && $0.type != .show)
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

    private func expectedBrowseEntries(
        library: Library,
        context: PlexAPIContext,
        includeCollections: Bool?,
        pageSize: Int
    ) async throws -> [BrowseParityEntry] {
        let sectionRepository = try SectionRepository(context: context)
        let sectionId = try sectionId(for: library)
        let typeValue = defaultBrowseTypeQueryValue(for: library)
        var entries: [BrowseParityEntry] = []
        var start = 0
        let maxPages = 300

        for page in 0..<maxPages {
            let includeMeta = page == 0
            let queryItems = [
                URLQueryItem(name: "type", value: typeValue),
                URLQueryItem(name: "includeCollections", value: includeCollections.map { $0 ? "1" : "0" }),
                URLQueryItem(name: "includeMeta", value: includeMeta ? "1" : "0")
            ].filter { $0.value != nil }

            let response = try await sectionRepository.getSectionBrowseItems(
                path: "/library/sections/\(sectionId)/all",
                queryItems: queryItems,
                pagination: PlexPagination(start: start, size: pageSize)
            )
            let metadata = response.mediaContainer.metadata ?? []
            if metadata.isEmpty {
                break
            }

            let pageEntries = metadata.compactMap { metadata in
                switch metadata {
                case let .folder(folder):
                    return BrowseParityEntry(kind: "folder", id: folder.key)
                case let .item(plexItem):
                    guard let displayItem = MediaDisplayItem(plexItem: plexItem) else {
                        return nil
                    }
                    guard isAllowedByPolicyInLibraryContext(displayItem, library: library) else {
                        return nil
                    }
                    return mediaEntry(displayItem)
                }
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

    private func expectedCollectionEntries(
        library: Library,
        context: PlexAPIContext,
        pageSize: Int
    ) async throws -> [BrowseParityEntry] {
        let sectionRepository = try SectionRepository(context: context)
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
                guard let displayItem = MediaDisplayItem(plexItem: plexItem),
                      StrimrAdapter.isAllowed(displayItem, policy: effectivePolicyFor(library)) else {
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

    private func defaultBrowseTypeQueryValue(for library: Library) -> String? {
        switch library.type {
        case .movie where !library.isNoneAgentLibrary:
            return "1"
        case .show:
            return "2"
        default:
            return nil
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

    private func effectivePolicyFor(_ library: Library) -> SafetyPolicy {
        guard library.isNoneAgentLibrary else { return policy }
        return SafetyPolicy.ratingOnly(
            maxMovie: policy.maxMovieRating,
            maxTV: policy.maxTVRating,
            allowUnrated: true
        )
    }

    private func isAllowedByPolicyInLibraryContext(_ item: MediaDisplayItem, library: Library) -> Bool {
        if HomeLibraryGrouping.isMoviesOrTV(library), case .collection = item {
            return false
        }
        switch item {
        case .collection, .playlist:
            return true
        case let .playable(media):
            let effectiveAllowUnrated = library.isNoneAgentLibrary || policy.allowUnrated
            return isAllowedByPolicyRating(media.contentRating, allowUnrated: effectiveAllowUnrated)
        }
    }

    private func isAllowedByPolicyRating(_ contentRating: String?, allowUnrated: Bool? = nil) -> Bool {
        let effectiveAllowUnrated = allowUnrated ?? policy.allowUnrated
        guard let contentRating, !contentRating.isEmpty else {
            return effectiveAllowUnrated
        }
        guard let rating = PlinxRating.from(contentRating: contentRating) else {
            return effectiveAllowUnrated
        }
        if rating.isTVRating {
            return rating <= policy.maxTVRating
        }
        return rating <= policy.maxMovieRating
    }
}
#endif
