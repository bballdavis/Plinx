@testable import Plinx
import XCTest

final class PlayerTimelineTests: XCTestCase {
    func test_validDurationRejectsMissingZeroNegativeAndNonFiniteValues() {
        XCTAssertNil(PlayerTimelinePolicy.validDuration(nil))
        XCTAssertNil(PlayerTimelinePolicy.validDuration(0))
        XCTAssertNil(PlayerTimelinePolicy.validDuration(-1))
        XCTAssertNil(PlayerTimelinePolicy.validDuration(.infinity))
        XCTAssertNil(PlayerTimelinePolicy.validDuration(.nan))
        XCTAssertEqual(PlayerTimelinePolicy.validDuration(90), 90)
    }

    func test_positionAndBufferValuesAreSanitizedBeforeRendering() {
        XCTAssertEqual(PlayerTimelinePolicy.clampedPosition(-4, duration: 100), 0)
        XCTAssertEqual(PlayerTimelinePolicy.clampedPosition(120, duration: 100), 100)
        XCTAssertEqual(PlayerTimelinePolicy.clampedPosition(.infinity, duration: 100), 0)
        XCTAssertEqual(
            PlayerTimelinePolicy.bufferedProgress(
                bufferedAhead: .infinity,
                playbackPosition: 35,
                duration: 100
            ),
            0.35
        )
        XCTAssertEqual(
            PlayerTimelinePolicy.bufferedProgress(
                bufferedAhead: 90,
                playbackPosition: 35,
                duration: 100
            ),
            1
        )
    }

    func test_handleCenterReachesExactTrackEndpoints() {
        let geometry = PlayerTimelineGeometry(width: 320, duration: 100, dotDiameter: 12)

        XCTAssertEqual(geometry.trackStart, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.trackEnd, 320, accuracy: 0.001)
        XCTAssertEqual(geometry.handleCenter(position: 0), geometry.trackStart, accuracy: 0.001)
        XCTAssertEqual(geometry.handleCenter(position: 100), geometry.trackEnd, accuracy: 0.001)
        XCTAssertEqual(geometry.handleCenter(position: 50), 160, accuracy: 0.001)
    }

    func test_touchMappingClampsOvershootToVideoEndpoints() {
        let geometry = PlayerTimelineGeometry(width: 320, duration: 100, dotDiameter: 12)

        XCTAssertEqual(geometry.position(forTouchX: -500) ?? -1, 0)
        XCTAssertEqual(geometry.position(forTouchX: 820) ?? -1, 100)
        XCTAssertEqual(geometry.position(forTouchX: 160) ?? -1, 50, accuracy: 0.001)
    }

    func test_invalidDurationHasNoTouchMapping() {
        let geometry = PlayerTimelineGeometry(width: 320, duration: .infinity, dotDiameter: 12)
        XCTAssertNil(geometry.position(forTouchX: 160))
        XCTAssertEqual(geometry.handleCenter(position: 70), geometry.trackStart, accuracy: 0.001)
    }

    func test_endpointHitTargetsRemainFullWidthAndShiftInward() {
        let geometry = PlayerTimelineGeometry(width: 320, duration: 100, dotDiameter: 12)
        let startTarget = geometry.handleHitRect(
            centerX: geometry.handleCenter(position: 0),
            controlHeight: 64
        )
        let endTarget = geometry.handleHitRect(
            centerX: geometry.handleCenter(position: 100),
            controlHeight: 64
        )

        XCTAssertEqual(startTarget.width, PlayerTimelinePolicy.minimumTouchTarget)
        XCTAssertEqual(endTarget.width, PlayerTimelinePolicy.minimumTouchTarget)
        XCTAssertEqual(startTarget.minX, 0)
        XCTAssertEqual(endTarget.maxX, 320)
        XCTAssertEqual(startTarget.height, 64)
    }

    func test_dragSessionPreservesFingerOffsetWithoutInitialJump() {
        let geometry = PlayerTimelineGeometry(width: 320, duration: 100, dotDiameter: 12)
        let handleCenter = geometry.handleCenter(position: 50)
        let session = PlayerTimelineDragSession(
            initialTouchX: handleCenter + 22,
            handleCenterX: handleCenter
        )

        XCTAssertFalse(session.shouldBegin(at: handleCenter + 24))
        XCTAssertTrue(session.shouldBegin(at: handleCenter + 25))
        XCTAssertTrue(session.shouldProcess(at: handleCenter + 22, isEditing: true))
        XCTAssertEqual(
            session.previewPosition(at: handleCenter + 22, geometry: geometry) ?? -1,
            50,
            accuracy: 0.001
        )
        XCTAssertEqual(
            session.previewPosition(at: session.initialTouchX + geometry.trackWidth / 2, geometry: geometry) ?? -1,
            100,
            accuracy: 0.001
        )
    }

    func test_accessibilityAdjustmentsUseValidRangeAndNoopAtEndpoints() {
        XCTAssertEqual(
            PlayerTimelinePolicy.accessibilityAdjustedPosition(
                position: 45,
                duration: 100,
                direction: 1
            ),
            55
        )
        XCTAssertNil(
            PlayerTimelinePolicy.accessibilityAdjustedPosition(
                position: 0,
                duration: 100,
                direction: -1
            )
        )
        XCTAssertNil(
            PlayerTimelinePolicy.accessibilityAdjustedPosition(
                position: 100,
                duration: 100,
                direction: 1
            )
        )
        XCTAssertNil(
            PlayerTimelinePolicy.accessibilityAdjustedPosition(
                position: 50,
                duration: nil,
                direction: 1
            )
        )
    }

    func test_tvStepPreservesUpstreamDurationBasedAcceleration() {
        XCTAssertEqual(PlayerTimelinePolicy.tvScrubStep(duration: nil), 10)
        XCTAssertEqual(PlayerTimelinePolicy.tvScrubStep(duration: 60), 5)
        XCTAssertEqual(PlayerTimelinePolicy.tvScrubStep(duration: 18_000), 60)
        XCTAssertEqual(PlayerTimelinePolicy.tvDelta(duration: 3_000, consecutiveMoves: 1), 10)
        XCTAssertEqual(PlayerTimelinePolicy.tvDelta(duration: 3_000, consecutiveMoves: 8), 50)
    }

    func test_timeFormattingSupportsHoursAndRejectsNonFiniteInput() {
        XCTAssertEqual(PlayerTimelinePolicy.formatTime(65), "01:05")
        XCTAssertEqual(PlayerTimelinePolicy.formatTime(3_661), "1:01:01")
        XCTAssertEqual(PlayerTimelinePolicy.formatTime(.nan), "00:00")
    }

    func test_editingLifecycleBeginsAndFinishesExactlyOnce() {
        var lifecycle = PlayerTimelineEditingLifecycle()

        XCTAssertTrue(lifecycle.begin())
        XCTAssertFalse(lifecycle.begin())
        XCTAssertTrue(lifecycle.finish())
        XCTAssertFalse(lifecycle.finish())
    }

    func test_newCommitGenerationRejectsStaleTimer() {
        var generation = PlayerTimelineCommitGeneration()
        let first = generation.schedule()
        let second = generation.schedule()

        XCTAssertFalse(generation.isCurrent(first))
        XCTAssertTrue(generation.isCurrent(second))
        generation.invalidate()
        XCTAssertFalse(generation.isCurrent(second))
    }
}
