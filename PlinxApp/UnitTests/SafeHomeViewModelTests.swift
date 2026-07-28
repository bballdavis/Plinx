import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class SafeHomeViewModelTests: XCTestCase {
    func test_loadUsesLibraryKeyedCatalogResultsAndKeepsPartialSuccess() async {
        let context = PlexAPIContext()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(userDefaults: defaults)
        let store = LibraryStore(context: context)
        let youtube = Library(id: "6", title: "YouTube", type: .movie, sectionId: 6, agent: "none")
        let broken = Library(id: "7", title: "Broken", type: .clip, sectionId: 7)
        store.libraries = [youtube, broken]
        let loader = FakeCatalogLoader(results: [
            youtube.id: LibraryCatalogResult(library: youtube, items: [item("youtube", rating: "TV-Y")])
        ], failingIDs: [broken.id])

        let viewModel = SafeHomeViewModel(
            context: context,
            settingsManager: settings,
            libraryStore: store,
            policy: .ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false),
            catalogLoader: loader
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.recentCatalogs.map(\.library.id), [youtube.id])
        XCTAssertEqual(viewModel.recentCatalogs.first?.items.map(\.id), ["youtube"])
        XCTAssertTrue(viewModel.hasContent)
    }

    func test_globalPolicyIsPassedToEveryLibraryIncludingYouTube() async {
        let context = PlexAPIContext()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(userDefaults: defaults)
        let store = LibraryStore(context: context)
        let youtube = Library(id: "6", title: "YouTube", type: .movie, sectionId: 6, agent: "none")
        store.libraries = [youtube]
        let loader = FakeCatalogLoader(results: [
            youtube.id: LibraryCatalogResult(library: youtube, items: [])
        ])
        let policy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)

        let viewModel = SafeHomeViewModel(
            context: context,
            settingsManager: settings,
            libraryStore: store,
            policy: policy,
            catalogLoader: loader
        )
        await viewModel.load()

        XCTAssertEqual(loader.policies, [policy])
        XCTAssertNil(viewModel.errorMessage, "A successful empty catalog is not a server failure")
    }

    func test_allCatalogRequestFailures_showLoadError() async {
        let context = PlexAPIContext()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(userDefaults: defaults)
        let store = LibraryStore(context: context)
        let library = Library(id: "6", title: "YouTube", type: .clip, sectionId: 6)
        store.libraries = [library]
        let loader = FakeCatalogLoader(results: [:], failingIDs: [library.id])
        let viewModel = SafeHomeViewModel(
            context: context,
            settingsManager: settings,
            libraryStore: store,
            catalogLoader: loader
        )

        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func test_reloadKeepsExistingContentWhenAllCatalogRequestsFail() async {
        let context = PlexAPIContext()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(userDefaults: defaults)
        let store = LibraryStore(context: context)
        let library = Library(id: "6", title: "YouTube", type: .clip, sectionId: 6)
        store.libraries = [library]
        let loader = FakeCatalogLoader(results: [
            library.id: LibraryCatalogResult(
                library: library,
                items: [item("existing", rating: "TV-Y")]
            )
        ])
        let viewModel = SafeHomeViewModel(
            context: context,
            settingsManager: settings,
            libraryStore: store,
            catalogLoader: loader
        )
        await viewModel.load()

        loader.results = [:]
        loader.failingIDs = [library.id]
        await viewModel.reload()

        XCTAssertEqual(viewModel.recentCatalogs.first?.items.map(\.id), ["existing"])
        XCTAssertTrue(viewModel.hasContent)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func item(_ id: String, rating: String?) -> MediaDisplayItem {
        .playable(MediaItem.fixture(id: id, type: .movie, contentRating: rating))
    }
}

@MainActor
private final class FakeCatalogLoader: LibraryCatalogLoading {
    var results: [String: LibraryCatalogResult]
    var failingIDs: Set<String>
    private(set) var policies: [SafetyPolicy] = []

    init(results: [String: LibraryCatalogResult], failingIDs: Set<String> = []) {
        self.results = results
        self.failingIDs = failingIDs
    }

    func recentItems(
        for library: Library,
        limit: Int,
        policy: SafetyPolicy
    ) async throws -> LibraryCatalogResult {
        policies.append(policy)
        if failingIDs.contains(library.id) { throw URLError(.cannotLoadFromNetwork) }
        return results[library.id] ?? LibraryCatalogResult(library: library, items: [])
    }
}

private extension MediaItem {
    static func fixture(id: String, type: PlexItemType, contentRating: String?) -> MediaItem {
        MediaItem(
            id: id, guid: "plex://\(id)", summary: nil, title: id, type: type,
            parentRatingKey: nil, grandparentRatingKey: nil, genres: [], year: nil,
            duration: nil, videoResolution: nil, rating: nil, ratings: [],
            contentRating: contentRating, studio: nil, tagline: nil, thumbPath: nil,
            artPath: nil, ultraBlurColors: nil, viewOffset: nil, viewCount: nil,
            childCount: nil, leafCount: nil, viewedLeafCount: nil,
            grandparentTitle: nil, parentTitle: nil, parentIndex: nil, index: nil,
            grandparentThumbPath: nil, grandparentArtPath: nil, parentThumbPath: nil
        )
    }
}
