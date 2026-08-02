import XCTest
@testable import Plinx

final class AppleTVBrowseFocusRoutingTests: XCTestCase {
    func test_headerReturnTarget_isAlwaysHomeWhenVisible() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(
            showSearchInMainNavigation: true,
            includeSettings: true
        )

        XCTAssertEqual(HeaderFocusOrder.returnTarget(visibleTabs: tabs), .home)
    }

    func test_headerReturnTarget_fallsBackToFirstRealTabWhenHomeIsMissing() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(showSearchInMainNavigation: true)
            .filter { $0.tab != .home }

        XCTAssertEqual(HeaderFocusOrder.returnTarget(visibleTabs: tabs), .library)
    }

    func test_upFromFirstHomeRow_routesToNavigation() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 0, rowCount: 3),
            .navigation
        )
    }

    func test_verticalHomeMovement_targetsFirstCardInAdjacentRow() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 0, rowCount: 3),
            .card(row: 1, item: 0)
        )
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 2, rowCount: 3),
            .card(row: 1, item: 0)
        )
    }

    func test_downFromLastHomeRow_doesNotMoveFocus() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 2, rowCount: 3),
            .unchanged
        )
    }

    func test_homeRouting_handlesSingleRowAndEmptyStates() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 0, rowCount: 1),
            .navigation
        )
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 0, rowCount: 1),
            .unchanged
        )
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 0, rowCount: 0),
            .unchanged
        )
    }
}
