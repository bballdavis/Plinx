import XCTest
@testable import Plinx

@MainActor
final class LibraryBrowseControlsViewModelTests: XCTestCase {

    func test_preferredNewestQuickSort_buildsDescendingAddedAtQuery() {
        let viewModel = LibraryBrowseControlsViewModel(context: PlexAPIContext())
        viewModel.preferredQuickSort = .newest
        viewModel.applyMeta(makeMeta())

        let items = viewModel.buildQueryItems(
            baseItems: [],
            includeCollections: false,
            includeMeta: false
        )

        XCTAssertEqual(
            items.first(where: { $0.name == "sort" })?.value,
            "addedAt:desc",
            "The Plinx browse UI defaults to newest first, so browse requests must use the descending addedAt sort once metadata is available."
        )
    }

    func test_preferredAlphabeticalQuickSort_buildsAscendingTitleQuery() {
        let viewModel = LibraryBrowseControlsViewModel(context: PlexAPIContext())
        viewModel.preferredQuickSort = .alphabetical
        viewModel.applyMeta(makeMeta())

        let items = viewModel.buildQueryItems(
            baseItems: [],
            includeCollections: false,
            includeMeta: false
        )

        XCTAssertEqual(
            items.first(where: { $0.name == "sort" })?.value,
            "titleSort",
            "Alphabetical browse should use the ascending title sort key."
        )
    }

    func test_applyMeta_notifiesWhenPreferredQuickSortBecomesAvailable() {
        let viewModel = LibraryBrowseControlsViewModel(context: PlexAPIContext())
        viewModel.preferredQuickSort = .newest

        var notifications = 0
        viewModel.onSelectionChanged = {
            notifications += 1
        }

        viewModel.applyMeta(makeMeta())

        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(viewModel.selectedSort?.sort.key, "addedAt")
        XCTAssertEqual(viewModel.selectedSort?.direction, .desc)
    }

    private func makeMeta() -> PlexSectionItemMeta {
        PlexSectionItemMeta(
            type: [
                PlexSectionItemMetaType(
                    key: "/library/sections/1/all?type=1",
                    type: .movie,
                    title: "Movies",
                    active: true,
                    filter: nil,
                    sort: [
                        PlexSectionItemSort(
                            active: nil,
                            activeDirection: nil,
                            defaultDirection: .asc,
                            defaultValue: nil,
                            descKey: "titleSort:desc",
                            key: "titleSort",
                            title: "Alphabetical"
                        ),
                        PlexSectionItemSort(
                            active: nil,
                            activeDirection: nil,
                            defaultDirection: .asc,
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