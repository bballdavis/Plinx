import SwiftUI
import XCTest
@testable import Plinx

final class PlinxPlayerControlLayoutTests: XCTestCase {
    func test_fullSizeTabletLayoutDoublesPrimaryControlSize() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.scale(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular
            ),
            2
        )
    }

    func test_compactLayoutsKeepControlGroupWithinSmallerScreens() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.scale(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular
            ),
            1.3
        )
        XCTAssertEqual(
            PlinxPlayerControlLayout.scale(
                horizontalSizeClass: .compact,
                verticalSizeClass: .compact
            ),
            1.45
        )
    }

    func test_regularWidthCompactHeightUsesIntermediateScale() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.scale(
                horizontalSizeClass: .regular,
                verticalSizeClass: .compact
            ),
            1.65
        )
    }

    func test_exitButtonUsesKidFriendlyTouchTargetAcrossSizeClasses() {
        XCTAssertEqual(
            PlinxPlayerControlLayout.exitButtonSize(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular
            ),
            80
        )
        XCTAssertEqual(
            PlinxPlayerControlLayout.exitButtonSize(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular
            ),
            104
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
