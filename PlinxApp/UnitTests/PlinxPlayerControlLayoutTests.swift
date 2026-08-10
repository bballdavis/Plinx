import XCTest
@testable import Plinx

final class PlinxPlayerControlLayoutTests: XCTestCase {
    func test_overlayHeaderUsesFiftyPercentEmphasis() {
        XCTAssertEqual(PlinxPlayerOverlayLayout.emphasisScale, 1.5)
        XCTAssertEqual(PlinxPlayerOverlayLayout.headerButtonSize, 63)
        XCTAssertEqual(PlinxPlayerOverlayLayout.headerIconSize, 25.5)
        XCTAssertEqual(PlinxPlayerOverlayLayout.headerCornerRadius, 21)
        XCTAssertEqual(PlinxPlayerOverlayLayout.titleSize, 30)
    }
}
