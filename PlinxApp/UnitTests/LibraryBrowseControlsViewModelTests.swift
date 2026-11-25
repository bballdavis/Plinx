import XCTest
@testable import Plinx

@MainActor
final class LibraryBrowseControlsViewModelTests: XCTestCase {
    private typealias PlexSelection = LibraryBrowsePreferences.PlexSelection

    private let movieTypeKey = "/library/sections/1/all?type=1"

    private var newestSelection: PlexSelection {
        PlexSelection(sortKey: "addedAt", sortDirection: .desc, sortQueryValue: "addedAt:desc")
    }

    func test_savedNewestSort_buildsDescendingAddedAtQuery() {
        let viewModel = LibraryBrowseControlsViewModel(advancedService: nil, pendingRestore: newestSelection)

        XCTAssertEqual(
            sortValue(viewModel),
            "addedAt:desc",
            "A saved newest-first sort must reach the very first browse request, before metadata is available."
        )

        viewModel.applyMeta(makeMeta())

        XCTAssertEqual(
            sortValue(viewModel),
            "addedAt:desc",
            "Once metadata confirms it, browse requests must keep the descending addedAt sort."
        )
    }

    func test_savedAlphabeticalSort_buildsAscendingTitleQuery() {
        let viewModel = LibraryBrowseControlsViewModel(
            advancedService: nil,
            pendingRestore: PlexSelection(sortKey: "titleSort", sortDirection: .asc, sortQueryValue: "titleSort")
        )
        viewModel.applyMeta(makeMeta())

        XCTAssertEqual(
            sortValue(viewModel),
            "titleSort",
            "Alphabetical browse should use the ascending title sort key."
        )
    }

    func test_applyMeta_confirmsSavedNewestSortWithoutRefresh() {
        let viewModel = LibraryBrowseControlsViewModel(advancedService: nil, pendingRestore: newestSelection)

        var notifications = 0
        viewModel.onSelectionChanged = {
            notifications += 1
        }

        let restoreChanged = viewModel.applyMeta(makeMeta())

        XCTAssertFalse(restoreChanged, "The first request already used the saved sort, so no refresh is needed.")
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(viewModel.selectedDisplayType?.key, movieTypeKey)
        XCTAssertEqual(viewModel.selectedSort?.sort.key, "addedAt")
        XCTAssertEqual(viewModel.selectedSort?.direction, PlexSortDirection.desc)
        XCTAssertEqual(viewModel.plexSelection.sortQueryValue, "addedAt:desc")
    }

    func test_applyMeta_requestsRefreshWhenSavedSortIsUnavailable() {
        let viewModel = LibraryBrowseControlsViewModel(
            advancedService: nil,
            pendingRestore: PlexSelection(sortKey: "removed", sortDirection: .desc, sortQueryValue: "removed:desc")
        )

        let restoreChanged = viewModel.applyMeta(makeMeta())

        XCTAssertTrue(restoreChanged, "A saved sort the library no longer offers must trigger a refresh.")
        XCTAssertEqual(viewModel.selectedSort?.sort.key, "titleSort")
        XCTAssertEqual(sortValue(viewModel), "titleSort")
    }

    func test_selectingDateAddedSort_buildsDescendingAddedAtQueryAndNotifies() {
        let viewModel = LibraryBrowseControlsViewModel(advancedService: nil)
        viewModel.applyMeta(makeMeta())

        var notifications = 0
        viewModel.onSelectionChanged = {
            notifications += 1
        }

        viewModel.selectSort(id: "addedAt")

        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(viewModel.selectedSort?.direction, PlexSortDirection.desc)
        XCTAssertEqual(sortValue(viewModel), "addedAt:desc")
        XCTAssertEqual(viewModel.plexSelection.sortQueryValue, "addedAt:desc")
    }

    private func sortValue(_ viewModel: LibraryBrowseControlsViewModel) -> String? {
        viewModel.buildQueryItems(
            baseItems: [],
            includeCollections: false,
            includeMeta: false
        )
        .first(where: { $0.name == "sort" })?
        .value
    }

    private func makeMeta() -> PlexSectionItemMeta {
        PlexSectionItemMeta(
            type: [
                PlexSectionItemMetaType(
                    key: movieTypeKey,
                    type: .movie,
                    title: "Movies",
                    active: true,
                    filter: nil,
                    sort: [
                        PlexSectionItemSort(
                            active: true,
                            activeDirection: .asc,
                            defaultDirection: .asc,
                            defaultValue: nil,
                            descKey: "titleSort:desc",
                            key: "titleSort",
                            title: "Alphabetical"
                        ),
                        PlexSectionItemSort(
                            active: nil,
                            activeDirection: nil,
                            defaultDirection: .desc,
                            defaultValue: nil,
                            descKey: "addedAt:desc",
                            key: "addedAt",
                            title: "Date Added"
                        )
                    ]
                )
            ]
        )
    }
}
