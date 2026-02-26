import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class LibraryFilteringParityLiveTests: XCTestCase {

    private let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)

    func test_liveRecommendedFilteringParity_movieLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let library = try await pickLibrary(type: .movie, context: context)
        try await assertRecommendedParity(library: library, context: context)
    }

    func test_liveRecommendedFilteringParity_showLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let library = try await pickLibrary(type: .show, context: context)
        try await assertRecommendedParity(library: library, context: context)
    }

    func test_liveBrowseFilteringParity_movieLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let library = try await pickLibrary(type: .movie, context: context)
        try await assertBrowseParity(library: library, context: context)
    }

    func test_liveBrowseFilteringParity_showLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let library = try await pickLibrary(type: .show, context: context)
        try await assertBrowseParity(library: library, context: context)
    }

    // MARK: - Parity assertions

    private func assertRecommendedParity(library: Library, context: PlexAPIContext) async throws {
        let hubRepository = try HubRepository(context: context)
        let response = try await hubRepository.getSectionHubs(sectionId: try sectionId(for: library))
        let rawHubs = (response.mediaContainer.hub ?? []).map(Hub.init)

        let expectedHubs = rawHubs.compactMap { hub -> Hub? in
            guard let safetyHub = StrimrAdapter.filtered(hub, policy: policy) else { return nil }
            let contextItems = safetyHub.items.filter { isAllowedInLibraryContext($0, library: library) }
            guard !contextItems.isEmpty else { return nil }
            return Hub(id: safetyHub.id, title: safetyHub.title, items: contextItems)
        }
        let expectedById = Dictionary(uniqueKeysWithValues: expectedHubs.map { ($0.id, $0) })

        let vm = LibraryRecommendedViewModel(library: library, context: context)
        vm.hubFilter = { [policy] hub in
            guard let safetyHub = StrimrAdapter.filtered(hub, policy: policy) else { return nil }
            let contextItems = safetyHub.items.filter { self.isAllowedInLibraryContext($0, library: library) }
            guard !contextItems.isEmpty else { return nil }
            return Hub(id: safetyHub.id, title: safetyHub.title, items: contextItems)
        }
        await vm.load()

        for hub in vm.hubs {
            guard let expectedHub = expectedById[hub.id] else {
                XCTFail("Unexpected recommended hub returned by filtered VM: \(hub.id)")
                continue
            }
            let expectedIds = Set(expectedHub.items.map(\.id))
            let actualIds = Set(hub.items.map(\.id))
            XCTAssertEqual(actualIds, expectedIds, "Recommended hub item parity mismatch for hub \(hub.id)")
            XCTAssertTrue(hub.items.allSatisfy { isAllowedInLibraryContext($0, library: library) },
                          "All recommended items must satisfy library-context safety policy")
        }
    }

    private func assertBrowseParity(library: Library, context: PlexAPIContext) async throws {
        let settings = SettingsManager()
        settings.setDisplayCollections(false)

        let vm = LibraryBrowseViewModel(library: library, context: context, settingsManager: settings)
        vm.itemFilter = { [policy] item in
            if HomeLibraryGrouping.isMoviesOrTV(library), case .collection = item {
                return false
            }
            return StrimrAdapter.isAllowed(item, policy: policy)
        }
        await vm.load()

        let rawExpectedIds = try await expectedBrowseMediaIDs(library: library, context: context, includeCollections: false)
        let displayedIds = Set(vm.browseItems.compactMap { item -> String? in
            guard case let .media(media) = item else { return nil }
            return media.id
        })

        XCTAssertEqual(displayedIds, rawExpectedIds, "Browse filtered media IDs must match repository parity for first page")
        XCTAssertTrue(vm.browseItems.allSatisfy { item in
            guard case let .media(media) = item else { return true }
            return isAllowedInLibraryContext(media, library: library)
        }, "All browse media items must satisfy library-context safety policy")
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
        var current = URL(fileURLWithPath: fm.currentDirectoryPath)

        for _ in 0..<5 {
            let candidate = current.appendingPathComponent("test_creds.yaml").path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            current.deleteLastPathComponent()
        }

        // Fallback: resolve from this source file path:
        // <repo>/PlinxApp/UnitTests/LibraryFilteringParityLiveTests.swift
        // -> <repo>/test_creds.yaml
        var sourceURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { sourceURL.deleteLastPathComponent() }
        let sourceCandidate = sourceURL.appendingPathComponent("test_creds.yaml").path
        if fm.fileExists(atPath: sourceCandidate) {
            return sourceCandidate
        }

        return nil
    }

    private func pickLibrary(type: PlexItemType, context: PlexAPIContext) async throws -> Library {
        let libraryStore = LibraryStore(context: context)
        try await libraryStore.loadLibraries()

        let candidate = libraryStore.libraries.first {
            $0.type == type && !$0.isNoneAgentLibrary && $0.sectionId != nil
        }

        guard let library = candidate else {
            throw XCTSkip("No eligible \(type.rawValue) library available for live parity test.")
        }
        return library
    }

    private func sectionId(for library: Library) throws -> Int {
        guard let sectionId = library.sectionId else {
            throw XCTSkip("Library \(library.title) is missing sectionId.")
        }
        return sectionId
    }

    private func expectedBrowseMediaIDs(
        library: Library,
        context: PlexAPIContext,
        includeCollections: Bool
    ) async throws -> Set<String> {
        let sectionRepository = try SectionRepository(context: context)
        let sectionId = try sectionId(for: library)
        let typeValue: String = library.type == .movie ? "1" : "2"
        let queryItems = [
            URLQueryItem(name: "type", value: typeValue),
            URLQueryItem(name: "includeCollections", value: includeCollections ? "1" : "0"),
            URLQueryItem(name: "includeMeta", value: "1")
        ]

        let response = try await sectionRepository.getSectionBrowseItems(
            path: "/library/sections/\(sectionId)/all",
            queryItems: queryItems,
            pagination: PlexPagination(start: 0, size: 20)
        )

        let safeMediaIDs = (response.mediaContainer.metadata ?? []).compactMap { metadata -> String? in
            guard case let .item(plexItem) = metadata,
                  let displayItem = MediaDisplayItem(plexItem: plexItem) else {
                return nil
            }
            return isAllowedInLibraryContext(displayItem, library: library) ? displayItem.id : nil
        }

        return Set(safeMediaIDs)
    }

    private func isAllowedInLibraryContext(_ item: MediaDisplayItem, library: Library) -> Bool {
        if HomeLibraryGrouping.isMoviesOrTV(library), case .collection = item {
            return false
        }
        return StrimrAdapter.isAllowed(item, policy: policy)
    }
}
