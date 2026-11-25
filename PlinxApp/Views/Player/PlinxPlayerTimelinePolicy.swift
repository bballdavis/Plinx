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
        // The dot and hump overhang the track ends instead of insetting the
        // track, preserving an exact 0...duration mapping across its width.
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

    /// Half the hump's width: from its peak to where a shoulder fillet meets
    /// the track tangentially. The crown circle is centered on the baseline,
    /// so the peak sits directly above the handle.
    static func humpHalfWidth(crownRadius: CGFloat, shoulderRadius: CGFloat) -> CGFloat {
        sqrt(crownRadius * crownRadius + 2 * crownRadius * shoulderRadius)
    }

    /// The hump is symmetric around the playback position, so its peak (the
    /// midpoint of this span) is exactly where playback is.
    func humpSpan(position: Double, halfWidth: CGFloat) -> ClosedRange<CGFloat> {
        let center = handleCenter(position: position)
        return (center - halfWidth)...(center + halfWidth)
    }

    /// The horizontal extent the track may draw into. The hump overhangs the
    /// track ends by its half width, so at 0 and at the duration the full hump
    /// stays visible with its peak on the track endpoint.
    func drawableSpan(humpHalfWidth: CGFloat) -> ClosedRange<CGFloat> {
        (trackStart - humpHalfWidth)...(trackEnd + humpHalfWidth)
    }

    /// The played color runs from the drawn start to the hump's peak, so the
    /// leading half of the hump is played and the trailing half is not.
    func playedSpan(position: Double, humpHalfWidth: CGFloat) -> ClosedRange<CGFloat> {
        let start = drawableSpan(humpHalfWidth: humpHalfWidth).lowerBound
        return start...max(start, handleCenter(position: position))
    }

    /// The buffered tint runs to the buffered position, measured the same way
    /// as the played span.
    func bufferedSpan(bufferedProgress: Double, humpHalfWidth: CGFloat) -> ClosedRange<CGFloat> {
        let start = drawableSpan(humpHalfWidth: humpHalfWidth).lowerBound
        let progress = bufferedProgress.isFinite ? min(max(bufferedProgress, 0), 1) : 0
        let end = trackStart + trackWidth * CGFloat(progress)
        return start...max(start, end)
    }

    /// The endpoint target shifts inward instead of being clipped in half.
    func handleHitRect(centerX: CGFloat, controlHeight: CGFloat) -> CGRect {
        let targetWidth = min(PlayerTimelinePolicy.minimumTouchTarget, width)
        let maximumOrigin = max(width - targetWidth, 0)
        let origin = min(max(centerX - (targetWidth / 2), 0), maximumOrigin)
        return CGRect(x: origin, y: 0, width: targetWidth, height: max(controlHeight, 0))
    }

    /// Where a time sits on the track; `nil` without a usable duration.
    func x(forTime time: Double) -> CGFloat? {
        guard let duration, time.isFinite else { return nil }
        let progress = min(max(time / duration, 0), 1)
        return trackStart + trackWidth * CGFloat(progress)
    }

    /// Track spans of the skip segments (intro, credits), clamped to the track. Empty or inverted ranges are dropped.
    func segmentSpans(_ marks: PlayerTimelineMarks) -> [ClosedRange<CGFloat>] {
        marks.segments.compactMap { segment in
            guard let start = x(forTime: segment.lowerBound),
                  let end = x(forTime: segment.upperBound),
                  end > start
            else { return nil }
            return start...end
        }
    }

    /// Gaps cut into the track where chapters begin, like the segmented upstream rail. A boundary too close to the
    /// track ends or to another boundary, or under the hump, gets no gap so the curve never breaks into slivers.
    func chapterGaps(
        _ marks: PlayerTimelineMarks,
        gapWidth: CGFloat,
        minimumSpacing: CGFloat,
        avoiding excluded: ClosedRange<CGFloat>?
    ) -> [ClosedRange<CGFloat>] {
        guard let duration, trackWidth > 0, gapWidth > 0 else { return [] }
        let starts = marks.chapterStarts
            .filter { $0.isFinite && $0 > 0 && $0 < duration }
            .sorted()
        var gaps: [ClosedRange<CGFloat>] = []
        var previousX = trackStart
        for start in starts {
            guard let x = x(forTime: start) else { continue }
            guard x - previousX >= minimumSpacing, trackEnd - x >= minimumSpacing else { continue }
            previousX = x
            if let excluded, excluded.contains(x) { continue }
            gaps.append((x - gapWidth / 2)...(x + gapWidth / 2))
        }
        return gaps
    }
}

/// Chapter starts and skip segments the timeline draws along its curve, in seconds.
struct PlayerTimelineMarks: Equatable {
    var chapterStarts: [Double]
    var segments: [ClosedRange<Double>]

    init(chapterStarts: [Double], segments: [ClosedRange<Double>]) {
        self.chapterStarts = chapterStarts
        self.segments = segments
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
