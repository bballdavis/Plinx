import XCTest
@testable import Plinx

final class PlinxPlayerControlLayoutTests: XCTestCase {
    func test_overlayHeaderUsesFiftyPercentEmphasis() {
        XCTAssertEqual(PlinxPlayerControlLayout.emphasisScale, 1.5)
        XCTAssertEqual(PlinxPlayerControlLayout.headerButtonSize, 63)
        XCTAssertEqual(PlinxPlayerControlLayout.headerIconSize, 25.5)
        XCTAssertEqual(PlinxPlayerControlLayout.headerCornerRadius, 21)
        XCTAssertEqual(PlinxPlayerControlLayout.titleSize, 30)
    }

    func test_exitButtonUsesKidFriendlyTouchTargetAcrossSizeClasses() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.exitButtonSize(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular
            ),
            63
        )
        XCTAssertEqual(
            PlinxPlayerControlLayout.exitButtonSize(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular
            ),
            63
        )
        XCTAssertGreaterThan(
            PlinxPlayerControlLayout.exitIconSize(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular
            ),
            20
        )
    }
}
