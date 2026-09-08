@testable import Plinx
import XCTest

final class PlinxPlayerControlLayoutTests: XCTestCase {
    func test_overlayHeaderUsesFiftyPercentEmphasis() {
        XCTAssertEqual(PlinxPlayerControlLayout.emphasisScale, 1.5)
        XCTAssertEqual(PlinxPlayerControlLayout.headerButtonSize, 63)
        XCTAssertEqual(PlinxPlayerControlLayout.headerIconSize, 25.5)
        XCTAssertEqual(PlinxPlayerControlLayout.headerCornerRadius, 21)
        XCTAssertEqual(PlinxPlayerControlLayout.titleSize, 30)
    }

    func test_transportControlsUseResponsiveScale() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.scale(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular
            ),
            2
        )
        XCTAssertEqual(
            PlinxPlayerControlLayout.scale(
                horizontalSizeClass: .regular,
                verticalSizeClass: .compact
            ),
            1.65
        )
    }

    func test_headerPresentationUsesContainerGeometry() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.headerPresentation(width: 390, height: 844),
            .compactPortrait
        )
        XCTAssertEqual(
            PlinxPlayerControlLayout.headerPresentation(width: 820, height: 1180),
            .spaciousPortrait
        )
        XCTAssertEqual(
            PlinxPlayerControlLayout.headerPresentation(width: 844, height: 390),
            .landscape
        )
    }

    func test_landscapeTitleWidthIsBoundedBetweenButtons() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.titleMaxWidth(width: 1366, presentation: .landscape),
            720
        )
        XCTAssertEqual(
            PlinxPlayerControlLayout.titleMaxWidth(width: 390, presentation: .compactPortrait),
            350
        )
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
