import XCTest
@testable import Plinx

final class KidsMainTabPickerTests: XCTestCase {

    func test_mainTabs_hidesDownloadsByDefault() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs()

        XCTAssertFalse(tabs.contains(where: { $0.id == "downloads" }))
    }

    func test_mainTabs_includesDownloadsWhenRequested() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(includeDownloads: true)

        XCTAssertTrue(tabs.contains(where: { $0.id == "downloads" }))
    }
}
