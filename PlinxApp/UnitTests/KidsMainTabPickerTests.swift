import XCTest
@testable import Plinx

final class KidsMainTabPickerTests: XCTestCase {

    func test_mainTabs_hidesSearchByDefault() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs()

        XCTAssertFalse(tabs.contains(where: { $0.id == "search" }))
    }

    func test_mainTabs_includesSearchWhenRequested() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(showSearchInMainNavigation: true)

        XCTAssertTrue(tabs.contains(where: { $0.id == "search" }))
    }

    func test_mainTabs_hidesDownloadsByDefault() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs()

        XCTAssertFalse(tabs.contains(where: { $0.id == "downloads" }))
    }

    func test_mainTabs_includesDownloadsWhenRequested() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(includeDownloads: true)

        XCTAssertTrue(tabs.contains(where: { $0.id == "downloads" }))
    }

    func test_mainTabs_includesSettingsWhenRequested() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(includeSettings: true)

        XCTAssertTrue(tabs.contains(where: { $0.id == "settings" }))
    }
}

final class QuickActionFocusOrderTests: XCTestCase {

    func test_focusIDs_appendCancelAfterOptions() {
        XCTAssertEqual(
            QuickActionFocusOrder.focusIDs(optionIDs: ["play", "details"]),
            ["play", "details", QuickActionFocusOrder.cancelID]
        )
    }

    func test_nextFocusedID_cyclesDownThroughOptionsAndCancel() {
        let optionIDs = ["play", "details"]

        XCTAssertEqual(
            QuickActionFocusOrder.nextFocusedID(current: nil, optionIDs: optionIDs, direction: .down),
            "play"
        )
        XCTAssertEqual(
            QuickActionFocusOrder.nextFocusedID(current: "play", optionIDs: optionIDs, direction: .down),
            "details"
        )
        XCTAssertEqual(
            QuickActionFocusOrder.nextFocusedID(current: "details", optionIDs: optionIDs, direction: .down),
            QuickActionFocusOrder.cancelID
        )
        XCTAssertEqual(
            QuickActionFocusOrder.nextFocusedID(current: QuickActionFocusOrder.cancelID, optionIDs: optionIDs, direction: .down),
            "play"
        )
    }

    func test_nextFocusedID_cyclesUpThroughOptionsAndCancel() {
        let optionIDs = ["play", "details"]

        XCTAssertEqual(
            QuickActionFocusOrder.nextFocusedID(current: "play", optionIDs: optionIDs, direction: .up),
            QuickActionFocusOrder.cancelID
        )
        XCTAssertEqual(
            QuickActionFocusOrder.nextFocusedID(current: QuickActionFocusOrder.cancelID, optionIDs: optionIDs, direction: .up),
            "details"
        )
    }
}

final class HeaderFocusOrderTests: XCTestCase {

    func test_nextPreferredTab_skipsCurrentHomeAndReturnsLibrary() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(showSearchInMainNavigation: true, includeSettings: true)

        XCTAssertEqual(
            HeaderFocusOrder.nextPreferredTab(current: .home, visibleTabs: tabs),
            .library
        )
    }

    func test_nextPreferredTab_skipsCurrentLibraryAndReturnsHome() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(showSearchInMainNavigation: true)

        XCTAssertEqual(
            HeaderFocusOrder.nextPreferredTab(current: .library, visibleTabs: tabs),
            .home
        )
    }

    func test_nextPreferredTab_ignoresActionOnlyItems() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(showSearchInMainNavigation: false, includeSettings: true)

        XCTAssertEqual(
            HeaderFocusOrder.nextPreferredTab(current: .library, visibleTabs: tabs),
            .home
        )
    }

    func test_nextPreferredTab_returnsHomeFromSearch() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(showSearchInMainNavigation: true)

        XCTAssertEqual(
            HeaderFocusOrder.nextPreferredTab(current: .search, visibleTabs: tabs),
            .home
        )
    }
}

#if os(tvOS)
final class HomeVerticalFocusRoutingTests: XCTestCase {

    func test_nextRoute_returnsNavigationWhenMovingUpFromTopRow() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 0, rowCount: 3),
            .navigation
        )
    }

    func test_nextRoute_returnsPreviousRowFirstItemWhenMovingUp() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 2, rowCount: 4),
            .card(row: 1, item: 0)
        )
    }

    func test_nextRoute_returnsNextRowFirstItemWhenMovingDown() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 1, rowCount: 4),
            .card(row: 2, item: 0)
        )
    }

    func test_nextRoute_returnsUnchangedWhenMovingDownFromLastRow() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 2, rowCount: 3),
            .unchanged
        )
    }
}
#endif
