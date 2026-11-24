@testable import Plinx
import XCTest
import AVFoundation

final class PlinxPlayerControlLayoutTests: XCTestCase {
    func test_landscapePlayerReclaimsEitherSideOfStatusSidebar() {
        let size = CGSize(width: 578, height: 466)
        let right = PlinxPlayerControlLayout.reclaimedStatusInsets(
            size: size, safeArea: .init(top: 0, leading: 0, bottom: 24, trailing: 100)
        )
        XCTAssertEqual(size.width + right.leading + right.trailing, 678)
        XCTAssertEqual(right.bottom, 0, "The home indicator must remain protected")
        let left = PlinxPlayerControlLayout.reclaimedStatusInsets(
            size: size, safeArea: .init(top: 0, leading: 100, bottom: 24, trailing: 0)
        )
        XCTAssertEqual(left.leading, 100)
        XCTAssertEqual(left.trailing, 0)
    }

    func test_playerPreservesPhoneNotchesAndPortraitSafeAreas() {
        let notch = PlinxPlayerControlLayout.reclaimedStatusInsets(
            size: CGSize(width: 832, height: 416),
            safeArea: .init(top: 0, leading: 62, bottom: 21, trailing: 62)
        )
        XCTAssertEqual(notch.leading + notch.trailing, 0)
        let portrait = PlinxPlayerControlLayout.reclaimedStatusInsets(
            size: CGSize(width: 366, height: 678),
            safeArea: .init(top: 0, leading: 0, bottom: 24, trailing: 100)
        )
        XCTAssertEqual(portrait.trailing, 0)
    }

    @MainActor
    func test_videoFillHandlesRendererReplacementAndRestoresFitOnTeardown() {
        let surface = CALayer()
        let native = AVPlayerLayer()
        surface.addSublayer(native)
        let adapter = PlinxVideoGravityAdapter()
        adapter.bind(to: surface)
        XCTAssertEqual(native.videoGravity, .resizeAspect)

        adapter.fillsScreen = true
        XCTAssertEqual(native.videoGravity, .resizeAspectFill)
        native.videoGravity = .resizeAspect
        XCTAssertEqual(native.videoGravity, .resizeAspectFill, "Reloading the source must preserve Fill")

        native.removeFromSuperlayer()
        let software = AVSampleBufferDisplayLayer()
        surface.addSublayer(software)
        XCTAssertEqual(software.videoGravity, .resizeAspectFill)
        XCTAssertEqual(native.videoGravity, .resizeAspect)
        adapter.fillsScreen = false
        XCTAssertEqual(software.videoGravity, .resizeAspect)
        adapter.fillsScreen = true
        adapter.unbind()
        XCTAssertEqual(software.videoGravity, .resizeAspect)
        software.videoGravity = .resize
        XCTAssertEqual(software.videoGravity, .resize, "Teardown must release all observers")
    }

    @MainActor
    func test_videoFillCanBeSelectedBeforeRendererArrives() {
        let surface = CALayer()
        let decoration = CALayer()
        surface.addSublayer(decoration)
        let adapter = PlinxVideoGravityAdapter()
        adapter.fillsScreen = true
        adapter.bind(to: surface)
        let native = AVPlayerLayer()
        surface.addSublayer(native)
        XCTAssertEqual(native.videoGravity, .resizeAspectFill)
        XCTAssertEqual(decoration.contentsGravity, .resize)
        adapter.unbind()
    }

    func test_onboardingUsesLandscapeColumnsAndExpandedPortrait() {
        XCTAssertEqual(PlinxOnboardingLayout(width: 851, height: 669), .expandedLandscape)
        XCTAssertEqual(PlinxOnboardingLayout(width: 569, height: 951), .regular)
        XCTAssertEqual(PlinxOnboardingLayout(width: 466, height: 678), .compact)
        XCTAssertEqual(PlinxOnboardingLayout(width: 1180, height: 820), .wide)
        XCTAssertEqual(PlinxOnboardingLayout(width: 844, height: 390), .regular)
    }

    func test_chromeReflowsFromClosedPhoneToOpenDisplay() {
        let closed = PlinxPlayerControlLayout.chromeInsets(width: 390, height: 780)
        let open = PlinxPlayerControlLayout.chromeInsets(width: 851, height: 669)
        XCTAssertEqual(closed.horizontal, 16)
        XCTAssertEqual(open.horizontal, 28)
        XCTAssertEqual(open.vertical, closed.vertical)
        XCTAssertEqual(open.bottomSpacing, 8)
    }

    func test_lockRowSitsJustAboveTimelineHumpWithoutOverlappingIt() {
        for size in [CGSize(width: 390, height: 780), CGSize(width: 844, height: 350)] {
            let insets = PlinxPlayerControlLayout.chromeInsets(width: size.width, height: size.height)
            let timeline = PlinxPlayerControlLayout.TouchTimeline.self
            // The row overlaps only the empty headroom above the hump.
            XCTAssertLessThan(insets.auxiliaryRowSpacing, 0)
            XCTAssertGreaterThan(insets.auxiliaryRowSpacing + timeline.humpPeakTop, 0)
            XCTAssertLessThanOrEqual(insets.bottomSpacing, 8)
        }
    }

    func test_touchTimelineTrackSitsNearBottomOfFullTouchTarget() {
        let timeline = PlinxPlayerControlLayout.TouchTimeline.self
        XCTAssertGreaterThanOrEqual(timeline.controlHeight, 64)
        XCTAssertLessThanOrEqual(timeline.controlHeight - timeline.baseline, 12)
        XCTAssertGreaterThan(timeline.humpPeakTop, 0)
    }

    func test_shortLandscapePreservesRoomForVideoAndTimeline() {
        let landscape = PlinxPlayerControlLayout.chromeInsets(width: 844, height: 350)
        XCTAssertEqual(landscape.horizontal, 28)
        XCTAssertEqual(landscape.vertical, 8)
        XCTAssertEqual(landscape.bottomSpacing, 6)
    }

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
