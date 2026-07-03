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
