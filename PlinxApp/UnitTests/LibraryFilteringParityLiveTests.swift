import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class LibraryFilteringParityLiveTests: XCTestCase {

    private let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)

    func test_liveRecommendedFilteringParity_movieLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let library = try await pickLibrary(type: .movie, context: context)

        let hubRepository = try HubRepository(context: context)
        let response = try await hubRepository.getSectionHubs(sectionId: try sectionId(for: library))
        let rawHubs = (response.mediaContainer.hub ?? []).map(Hub.init)
        let expectedHubs = rawHubs.compactMap { StrimrAdapter.filtered($0, policy: policy) }
        let expectedById = Dictionary(uniqueKeysWithValues: expectedHubs.map { ($0.id, $0) })

        let vm = LibraryRecommendedViewModel(library: library, context: context)
        vm.hubFilter = { StrimrAdapter.filtered($0, policy: self.policy) }
        await vm.load()

        for hub in vm.hubs {
            guard let expectedHub = expectedById[hub.id] else {
                XCTFail("Unexpected recommended hub returned by filtered VM: \(hub.id)")
                continue
            }
            let expectedIds = Set(expectedHub.items.map(\.id))
            let actualIds = Set(hub.items.map(\.id))
            XCTAssertEqual(actualIds, expectedIds, "Recommended hub item parity mismatch for hub \(hub.id)")
            XCTAssertTrue(hub.items.allSatisfy { StrimrAdapter.isAllowed($0, policy: policy) },
                          "All recommended items must satisfy safety policy")
        }
    }

    func test_liveBrowseFilteringParity_showLibrary() async throws {
        let context = try await makeLiveContextOrSkip()
        let library = try await pickLibrary(type: .show, context: context)

        let vm = LibraryBrowseViewModel(library: library, context: context, settingsManager: SettingsManager())
        vm.itemFilter = { StrimrAdapter.isAllowed($0, policy: self.policy) }
        await vm.load()

        let rawExpectedIds = try await expectedBrowseMediaIDs(library: library, context: context)
        let displayedIds = Set(vm.browseItems.compactMap { item -> String? in
            guard case let .media(media) = item else { return nil }
            return media.id
        })

        XCTAssertEqual(displayedIds, rawExpectedIds, "Browse filtered media IDs must match repository parity for first page")
        XCTAssertTrue(vm.browseItems.allSatisfy { item in
            guard case let .media(media) = item else { return true }
            return StrimrAdapter.isAllowed(media, policy: policy)
        }, "All browse media items must satisfy safety policy")
    }

    // MARK: - Helpers

    private func makeLiveContextOrSkip() async throws -> PlexAPIContext {
        let env = ProcessInfo.processInfo.environment
        guard let serverRaw = env["PLINX_PLEX_SERVER_URL"], !serverRaw.isEmpty,
              let token = env["PLINX_PLEX_TOKEN"], !token.isEmpty else {
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

    private func expectedBrowseMediaIDs(library: Library, context: PlexAPIContext) async throws -> Set<String> {
        let sectionRepository = try SectionRepository(context: context)
        let sectionId = try sectionId(for: library)
        let typeValue: String = library.type == .movie ? "1" : "2"
        let queryItems = [
            URLQueryItem(name: "type", value: typeValue),
            URLQueryItem(name: "includeCollections", value: "0"),
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
            return StrimrAdapter.isAllowed(displayItem, policy: policy) ? displayItem.id : nil
        }

        return Set(safeMediaIDs)
    }
}
