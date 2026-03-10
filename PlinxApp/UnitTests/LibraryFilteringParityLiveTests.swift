import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class LibraryFilteringParityLiveTests: XCTestCase {

    private let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
    private struct BrowseParityEntry: Equatable, Hashable {
        let kind: String
        let id: String
    }

    func test_liveRecommendedFilteringParity_movieLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .movie, context: context)
        for library in libraries {
            try await assertRecommendedParity(library: library, context: context)
        }
    }

    func test_liveRecommendedFilteringParity_showLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .show, context: context)
        for library in libraries {
            try await assertRecommendedParity(library: library, context: context)
        }
    }

    func test_liveBrowseFilteringParity_movieLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .movie, context: context)
        for library in libraries {
            try await assertBrowseParity(library: library, context: context)
        }
    }

    func test_liveBrowseFilteringParity_showLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .show, context: context)
        for library in libraries {
            try await assertBrowseParity(library: library, context: context)
        }
    }

    func test_liveBrowseFilteringParity_movieLibrary_fullPagination() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .movie, context: context)
        for library in libraries {
            try await assertBrowseParityFullPagination(library: library, context: context)
            try await assertBrowseParityFullPagination(
                library: library,
                context: context,
                quickSort: .newest
            )
        }
    }

    func test_liveBrowseFilteringParity_showLibrary_fullPagination() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickLibraries(type: .show, context: context)
        for library in libraries {
            try await assertBrowseParityFullPagination(library: library, context: context)
            try await assertBrowseParityFullPagination(
                library: library,
                context: context,
                quickSort: .newest
            )
        }
    }

    func test_liveBrowseFilteringParity_otherVideoLibrary_fullPagination() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickOtherVideoLibraries(context: context)
        for library in libraries {
            try await assertBrowseParityFullPagination(library: library, context: context)
            try await assertBrowseParityFullPagination(
                library: library,
                context: context,
                quickSort: .newest
            )
        }
    }

    func test_liveBrowseCompleteness_otherVideoLibrary_unfiltered() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickOtherVideoLibraries(context: context)

        let prioritized = libraries.sorted { lhs, rhs in
            let lhsIsYouTube = lhs.title.lowercased().contains("youtube")
            let rhsIsYouTube = rhs.title.lowercased().contains("youtube")
            if lhsIsYouTube == rhsIsYouTube {
                return lhs.title < rhs.title
            }
            return lhsIsYouTube && !rhsIsYouTube
        }

        for library in prioritized {
            try await assertBrowseCompletenessUnfiltered(library: library, context: context)
        }
    }

    func test_liveHomeRecentlyAdded_otherVideoHubVisibleUnderStrictPolicy() async throws {
        let context = try await makeLiveContextOrSkip()
        let settings = SettingsManager()
        let libraryStore = LibraryStore(context: context)
        try await libraryStore.loadLibraries()

        let eligibleLibraries = libraryStore.libraries.filter {
            $0.sectionId != nil && HomeLibraryGrouping.isOtherVideo($0)
        }
        guard !eligibleLibraries.isEmpty else {
            throw XCTSkip("No eligible Other Videos-style library available for live home recently-added test.")
        }

        let inner = HomeViewModel(context: context, settingsManager: settings, libraryStore: libraryStore)
        await inner.load()

        let recentlyAddedPrefix = NSLocalizedString("home.recentlyAdded.prefix", tableName: "Plinx", comment: "")
        let rawOtherHubIDs = Set(inner.recentlyAdded.compactMap { hub -> String? in
            let matched = HomeLibraryGrouping.matchLibrary(
                for: hub,
                in: libraryStore.libraries,
                recentlyAddedPrefix: recentlyAddedPrefix
            )
            return HomeLibraryGrouping.isOtherVideo(matched) ? hub.id : nil
        })

        guard !rawOtherHubIDs.isEmpty else {
            throw XCTSkip("Plex server did not return any raw Other Videos recently-added hubs for this account at this time.")
        }

        let permissivePolicy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: true)
        let safe = SafeHomeViewModel(inner: inner, policy: permissivePolicy, libraryStore: libraryStore)
        safe.updatePolicy(policy)

        let safeOtherHubIDs = Set(safe.recentlyAdded.compactMap { hub -> String? in
            let matched = HomeLibraryGrouping.matchLibrary(
                for: hub,
                in: libraryStore.libraries,
                recentlyAddedPrefix: recentlyAddedPrefix
            )
            return HomeLibraryGrouping.isOtherVideo(matched) ? hub.id : nil
        })

        XCTAssertFalse(
            safeOtherHubIDs.isEmpty,
            "SafeHomeViewModel should preserve at least one Other Videos recently-added hub under strict policy."
        )
        XCTAssertFalse(
            rawOtherHubIDs.intersection(safeOtherHubIDs).isEmpty,
            "At least one raw Other Videos hub should survive safety filtering."
        )
    }

    // MARK: - Parity assertions

    private func assertRecommendedParity(library: Library, context: PlexAPIContext) async throws {
        let hubRepository = try HubRepository(context: context)
        let response = try await hubRepository.getSectionHubs(sectionId: try sectionId(for: library))
        let rawHubs = (response.mediaContainer.hub ?? []).map(Hub.init)
        let expectedHubs = expectedRecommendedHubs(from: rawHubs, library: library)

        let vm = LibraryRecommendedViewModel(library: library, context: context)
        vm.hubFilter = { [policy] hub in
            guard let safetyHub = StrimrAdapter.filtered(hub, policy: policy) else { return nil }
            let contextItems = safetyHub.items.filter { self.isAllowedInAppContext($0, library: library) }
            guard !contextItems.isEmpty else { return nil }
            return Hub(id: safetyHub.id, title: safetyHub.title, items: contextItems)
        }
        await vm.load()

        XCTAssertEqual(
            vm.hubs.map(\.id),
            expectedHubs.map(\.id),
            "Recommended hub order/identity must match Plex+policy oracle"
        )
        XCTAssertEqual(vm.hubs.count, expectedHubs.count, "Recommended hub counts must match")

        for (actualHub, expectedHub) in zip(vm.hubs, expectedHubs) {
            let actualIds = actualHub.items.map(\.id)
            let expectedIds = expectedHub.items.map(\.id)
            XCTAssertEqual(
                actualIds,
                expectedIds,
                "Recommended hub item order/identity mismatch for hub \(actualHub.id)"
            )
            XCTAssertTrue(
                actualHub.items.allSatisfy { isAllowedByPolicyInLibraryContext($0, library: library) },
                "Recommended items must satisfy policy oracle"
            )
        }
    }

    private func assertBrowseParity(library: Library, context: PlexAPIContext) async throws {
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
        await vm.loadMore()

        let expectedEntries = try await expectedBrowseEntries(
            library: library,
            context: context,
            includeCollections: false,
            pages: 2,
            pageSize: 20
        )
        let actualEntries = vm.browseItems.map(browseEntry)
        let uniqueEntries = Set(actualEntries)
        XCTAssertEqual(
            uniqueEntries.count,
            actualEntries.count,
            "Browse results contain duplicate entries; this causes SwiftUI identity collisions in grids/carousels."
        )

        XCTAssertEqual(
            actualEntries,
            expectedEntries,
            "Browse entries must match Plex+policy oracle across initial pagination (including order)"
        )
        XCTAssertTrue(vm.browseItems.allSatisfy { item in
            guard case let .media(media) = item else { return true }
            return isAllowedByPolicyInLibraryContext(media, library: library)
        }, "All browse media items must satisfy library-context safety policy")
    }

    private func assertBrowseParityFullPagination(
        library: Library,
        context: PlexAPIContext,
        quickSort: LibraryBrowseControlsViewModel.QuickSort? = nil
    ) async throws {
        let settings = SettingsManager()
        settings.setDisplayCollections(false)

        let vm = LibraryBrowseViewModel(library: library, context: context, settingsManager: settings)
        vm.controls.preferredQuickSort = quickSort
        let effectivePolicy = effectivePolicyFor(library)
        vm.itemFilter = { [policy = effectivePolicy] item in
            if HomeLibraryGrouping.isMoviesOrTV(library), case .collection = item {
                return false
            }
            return StrimrAdapter.isAllowed(item, policy: policy)
        }

        await vm.load()

        // Keep advancing like the UI "load-more on last visible card" behavior.
        // Stop when there is no growth for several attempts to avoid infinite loops.
        var stagnantAttempts = 0
        var previousCount = vm.browseItems.count
        let maxLoadMoreAttempts = 300

        for _ in 0..<maxLoadMoreAttempts {
            await vm.loadMore()
            let currentCount = vm.browseItems.count
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

        let expectedEntries = try await expectedBrowseEntries(
            library: library,
            context: context,
            includeCollections: false,
            pages: nil,
            pageSize: 20,
            quickSort: quickSort
        )
        let actualEntries = vm.browseItems.map(browseEntry)
        let uniqueEntries = Set(actualEntries)
        XCTAssertEqual(
            uniqueEntries.count,
            actualEntries.count,
            "Browse results contain duplicate entries; this causes SwiftUI identity collisions in grids/carousels."
        )

        XCTAssertEqual(
            actualEntries,
            expectedEntries,
            "Browse entries must match Plex+policy oracle across full pagination (including order)"
        )
    }

    private func assertBrowseCompletenessUnfiltered(library: Library, context: PlexAPIContext) async throws {
        let settings = SettingsManager()
        settings.setDisplayCollections(false)

        let vm = LibraryBrowseViewModel(library: library, context: context, settingsManager: settings)
        vm.itemFilter = nil

        await vm.load()

        var stagnantAttempts = 0
        var previousCount = vm.browseItems.count
        let maxLoadMoreAttempts = 300

        for _ in 0..<maxLoadMoreAttempts {
            await vm.loadMore()
            let currentCount = vm.browseItems.count
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

        let expectedEntries = try await expectedBrowseEntries(
            library: library,
            context: context,
            includeCollections: false,
            pages: nil,
            pageSize: 200,
            applySafetyFilter: false
        )
        let actualEntries = vm.browseItems.map(browseEntry)
        let uniqueEntries = Set(actualEntries)

        XCTAssertEqual(
            uniqueEntries.count,
            actualEntries.count,
            "Unfiltered browse results contain duplicate entries; duplicates cause identity collisions and visible blank cells in the grid."
        )

        XCTAssertEqual(
            actualEntries,
            expectedEntries,
            "Unfiltered browse entries must match raw Plex oracle across full pagination for library: \(library.title)"
        )
    }

    // MARK: - Helpers

    private func makeLiveContextOrSkip() async throws -> PlexAPIContext {
        let serverRaw = credential(named: "PLINX_PLEX_SERVER_URL")
        let token = credential(named: "PLINX_PLEX_TOKEN")

        guard let serverRaw, !serverRaw.isEmpty,
              let token, !token.isEmpty else {
            throw XCTSkip("Live Plex credentials are not configured. Populate test_creds.yaml with PLINX_PLEX_SERVER_URL and PLINX_PLEX_TOKEN.")
        }

        guard let serverURL = URL(string: serverRaw),
              let host = serverURL.host,
              let scheme = serverURL.scheme else {
            XCTFail("Invalid PLINX_PLEX_SERVER_URL: \(serverRaw)")
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
            throw XCTSkip("Failed to connect to Plex server for live parity tests: \(error.localizedDescription)")
        }

        return context
    }

    private func credential(named key: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let direct = env[key], !direct.isEmpty {
            return direct
        }
        let simctlKey = "SIMCTL_CHILD_\(key)"
        if let simctl = env[simctlKey], !simctl.isEmpty {
            return simctl
        }
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            return stored
        }
        return yamlCredential(named: key)
    }

    private func yamlCredential(named key: String) -> String? {
        guard let yamlPath = locateTestCredsYAML(),
              let content = try? String(contentsOfFile: yamlPath, encoding: .utf8) else {
            return nil
        }

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: ":") else { continue }

            let parsedKey = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard parsedKey == key else { continue }

            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func locateTestCredsYAML() -> String? {
        let fm = FileManager.default

        // Most reliable path when running inside the iOS Simulator: the file is
        // bundled as a resource of the unit-test target, accessible via the bundle.
        if let bundlePath = Bundle(for: Self.self).path(forResource: "test_creds", ofType: "yaml") {
            return bundlePath
        }

        // macOS fallback: walk up from the working directory.
        var current = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<5 {
            let candidate = current.appendingPathComponent("test_creds.yaml").path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            current.deleteLastPathComponent()
        }

        // Last resort: resolve from this source file path.
        var sourceURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { sourceURL.deleteLastPathComponent() }
        let sourceCandidate = sourceURL.appendingPathComponent("test_creds.yaml").path
        if fm.fileExists(atPath: sourceCandidate) {
            return sourceCandidate
        }

        return nil
    }

    private func pickLibraries(type: PlexItemType, context: PlexAPIContext) async throws -> [Library] {
        let libraryStore = LibraryStore(context: context)
        try await libraryStore.loadLibraries()

        let candidates = libraryStore.libraries.filter {
            $0.type == type && !$0.isNoneAgentLibrary && $0.sectionId != nil
        }

        guard !candidates.isEmpty else {
            throw XCTSkip("No eligible \(type.rawValue) library available for live parity test.")
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

    private func expectedRecommendedHubs(
        from rawHubs: [Hub],
        library: Library
    ) -> [Hub] {
        rawHubs.compactMap { hub in
            let allowedItems = hub.items.filter { isAllowedByPolicyInLibraryContext($0, library: library) }
            guard !allowedItems.isEmpty else { return nil }
            return Hub(id: hub.id, title: hub.title, items: allowedItems)
        }
    }

    private func expectedBrowseEntries(
        library: Library,
        context: PlexAPIContext,
        includeCollections: Bool,
        pages: Int?,
        pageSize: Int,
        applySafetyFilter: Bool = true,
        quickSort: LibraryBrowseControlsViewModel.QuickSort? = nil
    ) async throws -> [BrowseParityEntry] {
        let sectionRepository = try SectionRepository(context: context)
        let sectionId = try sectionId(for: library)
        let typeValue = defaultBrowseTypeQueryValue(for: library)
        let sortValue = try await preferredSortQueryValue(
            quickSort,
            library: library,
            context: context,
            includeCollections: includeCollections,
            typeValue: typeValue,
            sectionRepository: sectionRepository
        )
        var entries: [BrowseParityEntry] = []
        var start = 0
        let maxPages = pages ?? 300

        for page in 0..<maxPages {
            let includeMeta = page == 0
            let queryItems = [
                URLQueryItem(name: "type", value: typeValue),
                URLQueryItem(name: "includeCollections", value: includeCollections ? "1" : "0"),
                URLQueryItem(name: "includeMeta", value: includeMeta ? "1" : "0"),
                URLQueryItem(name: "sort", value: sortValue)
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
                    if applySafetyFilter,
                       !isAllowedByPolicyInLibraryContext(displayItem, library: library)
                    {
                        return nil
                    }
                    return BrowseParityEntry(kind: "media", id: displayItem.id)
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

    private func preferredSortQueryValue(
        _ quickSort: LibraryBrowseControlsViewModel.QuickSort?,
        library: Library,
        context: PlexAPIContext,
        includeCollections: Bool,
        typeValue: String?,
        sectionRepository: SectionRepository
    ) async throws -> String? {
        guard let quickSort else { return nil }

        let controls = LibraryBrowseControlsViewModel(context: context)
        controls.preferredQuickSort = quickSort

        let queryItems = [
            URLQueryItem(name: "type", value: typeValue),
            URLQueryItem(name: "includeCollections", value: includeCollections ? "1" : "0"),
            URLQueryItem(name: "includeMeta", value: "1")
        ].filter { $0.value != nil }

        let response = try await sectionRepository.getSectionBrowseItems(
            path: "/library/sections/\(try sectionId(for: library))/all",
            queryItems: queryItems,
            pagination: PlexPagination(start: 0, size: 1)
        )

        guard let meta = response.mediaContainer.meta else { return nil }
        controls.applyMeta(meta)

        return controls.selectedSort.map { selection in
            selection.direction == .asc ? selection.sort.key : selection.sort.descKey
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

    private func effectivePolicyFor(_ library: Library) -> SafetyPolicy {
        // None-agent libraries (YouTube Videos, Home Videos, etc.) are personally
        // curated and typically lack MPAA/TV content ratings. Allow unrated items
        // through while still respecting the rating ceiling for any rated item.
        guard library.isNoneAgentLibrary else { return policy }
        return SafetyPolicy.ratingOnly(
            maxMovie: policy.maxMovieRating,
            maxTV: policy.maxTVRating,
            allowUnrated: true
        )
    }

    private func isAllowedInAppContext(_ item: MediaDisplayItem, library: Library) -> Bool {
        if HomeLibraryGrouping.isMoviesOrTV(library), case .collection = item {
            return false
        }
        return StrimrAdapter.isAllowed(item, policy: effectivePolicyFor(library))
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
