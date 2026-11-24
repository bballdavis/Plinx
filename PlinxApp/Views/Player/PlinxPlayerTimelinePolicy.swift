import CoreGraphics
import Foundation

/// Pure timeline math shared by the touch and focus implementations.
///
/// Keeping the seek mapping here makes the visual endpoints, hit target, and
/// input paths agree on what zero and duration mean.
enum PlayerTimelinePolicy {
    static let minimumTouchTarget: CGFloat = 64
    static let touchStartThreshold: CGFloat = 3

    static func validDuration(_ duration: Double?) -> Double? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    static func finitePosition(_ position: Double) -> Double {
        position.isFinite ? max(position, 0) : 0
    }

    static func clampedPosition(_ position: Double, duration: Double?) -> Double {
        let position = finitePosition(position)
        guard let duration = validDuration(duration) else { return position }
        return min(position, duration)
    }

    static func progress(position: Double, duration: Double?) -> Double {
        guard let duration = validDuration(duration) else { return 0 }
        return min(max(clampedPosition(position, duration: duration) / duration, 0), 1)
    }

    static func bufferedProgress(
        bufferedAhead: Double,
        playbackPosition: Double,
        duration: Double?
    ) -> Double {
        guard let duration = validDuration(duration) else { return 0 }
        let base = clampedPosition(playbackPosition, duration: duration)
        let ahead = bufferedAhead.isFinite ? max(bufferedAhead, 0) : 0
        return min(max((base + ahead) / duration, 0), 1)
    }

    static func formatTime(_ seconds: Double) -> String {
        let safeSeconds = seconds.isFinite ? max(seconds, 0) : 0
        // `Int(Double.greatestFiniteMagnitude)` traps. This upper bound is
        // still far beyond a plausible video duration while keeping conversion
        // safe on every supported architecture.
        let totalSeconds = Int(min(safeSeconds.rounded(.down), 9_000_000_000_000_000))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d:%02d", minutes, seconds))"
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func accessibilityAdjustedPosition(
        position: Double,
        duration: Double?,
        direction: Int,
        step: Double = 10
    ) -> Double? {
        guard let duration = validDuration(duration), direction != 0 else { return nil }
        let current = clampedPosition(position, duration: duration)
        let candidate = min(max(current + (Double(direction) * step), 0), duration)
        return candidate == current ? nil : candidate
    }

    static func tvScrubStep(duration: Double?) -> Double {
        guard let duration = validDuration(duration) else { return 10 }
        return min(max(duration / 300, 5), 60)
    }

    static func tvDelta(duration: Double?, consecutiveMoves: Int) -> Double {
        tvScrubStep(duration: duration) * min(max(Double(consecutiveMoves), 1), 5)
    }
}

struct PlayerTimelineGeometry: Equatable {
    let width: CGFloat
    let horizontalInset: CGFloat
    let duration: Double?

    init(width: CGFloat, duration: Double?, dotDiameter: CGFloat) {
        self.width = max(width.isFinite ? width : 0, 0)
        // The dot is outside the clipped track layer. Its controlled overhang
        // preserves an exact 0...duration mapping across the entire track.
        horizontalInset = 0
        self.duration = PlayerTimelinePolicy.validDuration(duration)
    }

    var trackStart: CGFloat { horizontalInset }
    var trackEnd: CGFloat { max(trackStart, width - horizontalInset) }
    var trackWidth: CGFloat { max(trackEnd - trackStart, 0) }

    func handleCenter(position: Double) -> CGFloat {
        trackStart + (trackWidth * CGFloat(PlayerTimelinePolicy.progress(position: position, duration: duration)))
    }

    func position(forTouchX touchX: CGFloat) -> Double? {
        guard let duration, trackWidth > 0 else { return nil }
        let x = min(max(touchX, trackStart), trackEnd)
        let progress = Double((x - trackStart) / trackWidth)
        return min(max(progress * duration, 0), duration)
    }

    /// The endpoint target shifts inward instead of being clipped in half.
    func handleHitRect(centerX: CGFloat, controlHeight: CGFloat) -> CGRect {
        let targetWidth = min(PlayerTimelinePolicy.minimumTouchTarget, width)
        let maximumOrigin = max(width - targetWidth, 0)
        let origin = min(max(centerX - (targetWidth / 2), 0), maximumOrigin)
        return CGRect(x: origin, y: 0, width: targetWidth, height: max(controlHeight, 0))
    }
}

struct PlayerTimelineDragSession: Equatable {
    let initialTouchX: CGFloat
    let handleCenterX: CGFloat

    var handleOffset: CGFloat { initialTouchX - handleCenterX }

    func shouldBegin(at touchX: CGFloat) -> Bool {
        abs(touchX - initialTouchX) >= PlayerTimelinePolicy.touchStartThreshold
    }

    /// Once editing began, a finger may travel back across its original point
    /// without accidentally suppressing the final preview update.
    func shouldProcess(at touchX: CGFloat, isEditing: Bool) -> Bool {
        isEditing || shouldBegin(at: touchX)
    }

    func previewPosition(at touchX: CGFloat, geometry: PlayerTimelineGeometry) -> Double? {
        geometry.position(forTouchX: touchX - handleOffset)
    }
}

/// Idempotent editing transitions make cancellation, disappearance, and a
/// delayed TV commit safe even when more than one lifecycle event arrives.
struct PlayerTimelineEditingLifecycle: Equatable {
    private(set) var isEditing = false

    mutating func begin() -> Bool {
        guard !isEditing else { return false }
        isEditing = true
        return true
    }

    mutating func finish() -> Bool {
        guard isEditing else { return false }
        isEditing = false
        return true
    }
}

struct PlayerTimelineCommitGeneration: Equatable {
    private(set) var value = 0

    mutating func schedule() -> Int {
        value += 1
        return value
    }

    mutating func invalidate() {
        value += 1
    }

    func isCurrent(_ candidate: Int) -> Bool {
        candidate == value
    }
}
