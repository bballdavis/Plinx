import SwiftUI
import UIKit

/// Plinx's large, handle-first player timeline: a track with a raised hump at
/// the playback position.
///
/// It is the only `PlayerTimelineView`, used by the iOS controls, the iOS
/// tabletop (Duo) layout and the tvOS controls, so it takes the full upstream
/// parameter list. Chapters are drawn as gaps along the curve and skip
/// segments (intro, credits) as tinted spans; a scrub shows the preview frame,
/// the chapter title and, when enabled, the time playback will end.
struct PlayerTimelineView: View {
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var playbackPosition: Double
    var showsEndsAtTime = false
    var chapters: [MediaChapter] = []
    var showsChaptersOnTimeline = false
    var skipSegments: [SkipSegment] = []
    var scrubPreview: PlayerScrubPreview?
    var onEditingChanged: (Bool) -> Void
    /// Draws the scrub preview and chapter title above the timeline instead of inserting them, so a timeline laid out
    /// among other controls keeps its height while scrubbing.
    var floatsScrubDetails = false
    /// Back during a tvOS scrub: the preview ends without seeking. Without it, Back commits the scrub.
    var onCancel: (() -> Void)?
    /// Whether a swipe on the tvOS touch surface scrubs; the players allow it only while paused.
    var swipesScrub = true
    /// A tvOS swipe that does not scrub, which still counts as an interaction with the controls.
    var onIdleSwipe: () -> Void = {}

    @State private var isEditing = false
    #if !os(tvOS)
        @State private var touchPreview: Double?
        @State private var touchLifecycle = PlayerTimelineEditingLifecycle()
        @Environment(\.scenePhase) private var scenePhase
    #endif

    private var isAvailable: Bool {
        PlayerTimelinePolicy.validDuration(duration) != nil
    }

    private var displayPosition: Double {
        #if os(tvOS)
            PlayerTimelinePolicy.clampedPosition(position, duration: duration)
        #else
            touchPreview ?? PlayerTimelinePolicy.clampedPosition(position, duration: duration)
        #endif
    }

    private var marks: PlayerTimelineMarks {
        PlayerTimelineMarks(
            chapterStarts: showsChaptersOnTimeline ? chapters.filter(\.isValid).map(\.startTime) : [],
            segments: skipSegments.compactMap { segment in
                guard segment.startTime.isFinite, segment.endTime.isFinite, segment.endTime > segment.startTime else {
                    return nil
                }
                return segment.startTime...segment.endTime
            }
        )
    }

    private var elapsedText: String {
        isAvailable ? PlayerTimelinePolicy.formatTime(displayPosition) : "--:--"
    }

    private var remainingText: String {
        guard let duration = PlayerTimelinePolicy.validDuration(duration) else { return "--:--" }
        return "-\(PlayerTimelinePolicy.formatTime(max(duration - displayPosition, 0)))"
    }

    private var labelSpacing: CGFloat {
        #if os(tvOS)
            6
        #else
            // The track sits near the bottom of its touch target, so the time
            // labels follow directly beneath it.
            0
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            if !floatsScrubDetails, hasScrubDetails {
                scrubDetails
            }

            track

            timeLabels
        }
        .overlay(alignment: .top) {
            if floatsScrubDetails, hasScrubDetails {
                // A zero-height frame anchored at the bottom grows the details upward from the top of the timeline.
                scrubDetails
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 0, alignment: .bottom)
                    .offset(y: -Self.floatingDetailsGap)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 24)
        #if os(tvOS)
            .padding(.vertical, 8)
        #else
            .padding(.bottom, 8)
        #endif
    }

    /// Clears the timeline's padding and a tile drawn around it.
    private static let floatingDetailsGap: CGFloat = 24

    @ViewBuilder
    private var track: some View {
        #if os(tvOS)
            PlayerRaisedHumpTVTimeline(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: playbackPosition,
                marks: marks,
                swipesScrub: swipesScrub,
                onEditingChanged: setEditing,
                onCancel: cancelHandler,
                onIdleSwipe: onIdleSwipe
            )
            .accessibilityHint(String(localized: "player.timeline.tvHint", table: "Plinx"))
        #else
            PlayerRaisedHumpTouchTimeline(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: playbackPosition,
                marks: marks,
                preview: touchPreview,
                onBegin: beginTouchEditing,
                onUpdate: updateTouchEditing,
                onFinish: finishTouchEditing,
                onLayoutChanged: finishTouchEditing
            )
            .accessibilityHint(String(localized: "player.timeline.hint", table: "Plinx"))
            .onChange(of: duration) { _, newDuration in
                guard touchLifecycle.isEditing else { return }
                guard PlayerTimelinePolicy.validDuration(newDuration) != nil else {
                    position = PlayerTimelinePolicy.finitePosition(playbackPosition)
                    finishTouchEditing()
                    return
                }
                let clampedPreview = PlayerTimelinePolicy.clampedPosition(
                    touchPreview ?? position,
                    duration: newDuration
                )
                touchPreview = clampedPreview
                position = clampedPreview
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active { finishTouchEditing() }
            }
        #endif
    }

    private var timeLabels: some View {
        HStack(alignment: .top) {
            Text(elapsedText)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(remainingText)
                if showsEndsAtTime {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if let endsAtText = playerEndsAtText(
                            position: displayPosition,
                            duration: PlayerTimelinePolicy.validDuration(duration),
                            now: context.date
                        ) {
                            Text(endsAtText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                }
            }
            .fixedSize()
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.white.opacity(0.9))
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    /// The scrub preview frame, while scrubbing a timeline that has one.
    private var previewDuringScrub: (preview: PlayerScrubPreview, duration: Double)? {
        guard isEditing,
              let scrubPreview,
              scrubPreview.image != nil,
              let duration = PlayerTimelinePolicy.validDuration(duration)
        else { return nil }
        return (scrubPreview, duration)
    }

    /// The chapter under the playhead, while scrubbing with chapters shown.
    private var chapterDuringScrub: MediaChapter? {
        guard showsChaptersOnTimeline, isEditing else { return nil }
        return chapter(at: displayPosition)
    }

    private var hasScrubDetails: Bool {
        previewDuringScrub != nil || chapterDuringScrub != nil
    }

    /// Optional on purpose: without the player's cancel, the tvOS timeline commits on Back instead.
    private var cancelHandler: (() -> Void)? {
        guard let onCancel else { return nil }
        return {
            withAnimation(Motion.crossfade) {
                isEditing = false
            }
            onCancel()
        }
    }

    private var scrubDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let scrub = previewDuringScrub {
                // The track has no inset: the card follows the handle across the full width.
                PlayerScrubPreviewRail(preview: scrub.preview, duration: scrub.duration, horizontalInset: 0)
                    .transition(.opacity)
            }

            if let chapter = chapterDuringScrub {
                Text(chapter.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 10)
        .accessibilityHidden(true)
    }

    private func chapter(at time: Double) -> MediaChapter? {
        chapters.first { $0.contains(time: time) }
    }

    private func setEditing(_ editing: Bool) {
        withAnimation(Motion.crossfade) {
            isEditing = editing
        }
        onEditingChanged(editing)
    }

    #if !os(tvOS)
        private func beginTouchEditing(_ preview: Double) {
            guard isAvailable, touchLifecycle.begin() else { return }
            // The parent copies its authoritative playback position in this callback.
            // Set the preview only after it has done so, avoiding a first-drag jump.
            setEditing(true)
            let resolved = PlayerTimelinePolicy.clampedPosition(preview, duration: duration)
            touchPreview = resolved
            position = resolved
        }

        private func updateTouchEditing(_ preview: Double) {
            guard touchLifecycle.isEditing else { return }
            let resolved = PlayerTimelinePolicy.clampedPosition(preview, duration: duration)
            touchPreview = resolved
            position = resolved
        }

        private func finishTouchEditing() {
            guard touchLifecycle.finish() else { return }
            if PlayerTimelinePolicy.validDuration(duration) == nil {
                position = PlayerTimelinePolicy.finitePosition(playbackPosition)
            } else {
                position = PlayerTimelinePolicy.clampedPosition(position, duration: duration)
            }
            touchPreview = nil
            setEditing(false)
        }
    #endif
}

/// The wall-clock time playback ends; `nil` without a usable duration. Plinx always plays at normal speed.
func playerEndsAtText(
    position: Double,
    duration: Double?,
    now: Date
) -> String? {
    guard let duration,
          duration.isFinite,
          duration > 0,
          position.isFinite,
          position >= 0
    else {
        return nil
    }

    let endDate = now.addingTimeInterval(max(duration - position, 0))
    let time = endDate.formatted(date: .omitted, time: .shortened)
    return String(localized: "player.timeline.endsAt \(time)")
}

/// The scrub preview frame, kept over its position on the timeline and inside the timeline's width.
struct PlayerScrubPreviewRail: View {
    var preview: PlayerScrubPreview
    var duration: Double
    var horizontalInset: CGFloat = 14

    private var cardSize: CGSize {
        #if os(tvOS)
            CGSize(width: 256, height: 144)
        #else
            CGSize(width: 180, height: 101.25)
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usableWidth = max(width - horizontalInset * 2, 0)
            let progress = duration > 0
                ? min(max(preview.position / duration, 0), 1)
                : 0
            let targetX = horizontalInset + usableWidth * CGFloat(progress)
            let halfCardWidth = cardSize.width / 2
            let cardX = min(
                max(targetX, halfCardWidth),
                max(halfCardWidth, width - halfCardWidth)
            )

            if let image = preview.image {
                PlayerScrubPreviewCard(
                    image: image,
                    position: preview.position,
                    size: cardSize
                )
                .position(x: cardX, y: cardSize.height / 2)
            }
        }
        .frame(height: cardSize.height)
        .accessibilityElement(children: .combine)
    }
}

struct PlayerScrubPreviewCard: View {
    var image: CGImage
    var position: Double
    var size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            Color.black.opacity(0.72)

            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .id(ObjectIdentifier(image))
                .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            Text(PlayerTimelinePolicy.formatTime(position))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.62)))
                .padding(8)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.brandPrimary.opacity(0.52), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 7)
        .animation(Motion.crossfade, value: ObjectIdentifier(image))
    }
}

private enum PlayerTimelineMetrics {
    #if os(tvOS)
        static let controlHeight: CGFloat = 88
        static let trackThickness: CGFloat = 8
        static let humpWidth: CGFloat = 84
        static let humpRise: CGFloat = 34
        static let crownRadius: CGFloat = 34
        static let shoulderRadius: CGFloat = 8
        static let dotDiameter: CGFloat = 18
        static let baseline: CGFloat = 61
        static let chapterGapWidth: CGFloat = 5
    #else
        static let controlHeight = PlinxPlayerControlLayout.TouchTimeline.controlHeight
        static let trackThickness = PlinxPlayerControlLayout.TouchTimeline.trackThickness
        static let humpWidth: CGFloat = 56
        static let humpRise = PlinxPlayerControlLayout.TouchTimeline.humpRise
        static let crownRadius = PlinxPlayerControlLayout.TouchTimeline.humpRise
        static let shoulderRadius: CGFloat = 6
        static let dotDiameter: CGFloat = 12
        static let baseline = PlinxPlayerControlLayout.TouchTimeline.baseline
        static let chapterGapWidth: CGFloat = 4
    #endif

    /// A chapter gap needs at least this much track on each side, so short chapters do not shred the curve.
    static var chapterMinimumSpacing: CGFloat {
        trackThickness + chapterGapWidth * 2
    }
}

private struct PlayerRaisedHumpTrack: View {
    let position: Double
    let duration: Double?
    let bufferedAhead: Double
    let playbackPosition: Double
    let marks: PlayerTimelineMarks
    let isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let geometry = PlayerTimelineGeometry(
                width: proxy.size.width,
                duration: duration,
                dotDiameter: PlayerTimelineMetrics.dotDiameter
            )
            let handleX = geometry.handleCenter(position: position)
            let humpHalfWidth = PlayerTimelineGeometry.humpHalfWidth(
                crownRadius: PlayerTimelineMetrics.crownRadius,
                shoulderRadius: PlayerTimelineMetrics.shoulderRadius
            )
            let bufferedSpan = geometry.bufferedSpan(
                bufferedProgress: PlayerTimelinePolicy.bufferedProgress(
                    bufferedAhead: bufferedAhead,
                    playbackPosition: playbackPosition,
                    duration: duration
                ),
                humpHalfWidth: humpHalfWidth
            )
            // Played color stops at the hump's peak: the peak is the playback
            // position, so only the hump's leading half reads as played.
            let playedSpan = geometry.playedSpan(position: position, humpHalfWidth: humpHalfWidth)
            let drawableSpan = geometry.drawableSpan(humpHalfWidth: humpHalfWidth)
            let segmentSpans = geometry.segmentSpans(marks)
            // The hump stays one smooth arch: no chapter gap is cut under it.
            let chapterGaps = geometry.chapterGaps(
                marks,
                gapWidth: PlayerTimelineMetrics.chapterGapWidth,
                minimumSpacing: PlayerTimelineMetrics.chapterMinimumSpacing,
                avoiding: geometry.humpSpan(position: position, halfWidth: humpHalfWidth)
            )

            ZStack {
                ZStack {
                    curve(geometry: geometry, handleX: handleX)
                        .stroke(Color.white.opacity(0.34), style: timelineStrokeStyle)

                    curve(geometry: geometry, handleX: handleX)
                        .stroke(Color.white.opacity(0.63), style: timelineStrokeStyle)
                        .mask(alignment: .topLeading) {
                            spanMask(bufferedSpan, height: proxy.size.height)
                        }

                    // Skip segments (intro, credits) ahead of the playhead read
                    // as tinted spans; once played they turn white like the rest.
                    if !segmentSpans.isEmpty {
                        curve(geometry: geometry, handleX: handleX)
                            .stroke(Color.brandPrimary.opacity(0.85), style: timelineStrokeStyle)
                            .mask(alignment: .topLeading) {
                                spansMask(segmentSpans, height: proxy.size.height)
                            }
                    }

                    curve(geometry: geometry, handleX: handleX)
                        .stroke(Color.white, style: timelineStrokeStyle)
                        .mask(alignment: .topLeading) {
                            spanMask(playedSpan, height: proxy.size.height)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 7, x: 0, y: 4)
                }
                // The hump may overhang the track ends so it is never cut in
                // half at the start or end of the video. Chapter starts are
                // cut out of the curve as small gaps.
                .mask(alignment: .topLeading) {
                    trackMask(drawableSpan, gaps: chapterGaps, height: proxy.size.height)
                }

                Circle()
                    .fill(isFocused ? Color.accentColor : .white)
                    .frame(
                        width: PlayerTimelineMetrics.dotDiameter,
                        height: PlayerTimelineMetrics.dotDiameter
                    )
                    .scaleEffect(isFocused ? 1.25 : 1)
                    .shadow(color: .black.opacity(0.42), radius: 5, x: 0, y: 3)
                    .position(x: handleX, y: PlayerTimelineMetrics.baseline)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: PlayerTimelineMetrics.controlHeight,
            maxHeight: PlayerTimelineMetrics.controlHeight
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func curve(geometry: PlayerTimelineGeometry, handleX: CGFloat) -> PlayerTimelineCurve {
        PlayerTimelineCurve(
            trackStart: geometry.trackStart,
            trackEnd: geometry.trackEnd,
            handleCenter: handleX
        )
    }

    /// A full-height rectangle covering `span` in the track's coordinates.
    private func spanMask(_ span: ClosedRange<CGFloat>, height: CGFloat) -> some View {
        Rectangle()
            .frame(width: max(span.upperBound - span.lowerBound, 0), height: height)
            .offset(x: span.lowerBound)
    }

    private func spansMask(_ spans: [ClosedRange<CGFloat>], height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                spanMask(span, height: height)
            }
        }
    }

    /// The drawable span with each gap punched out of it.
    private func trackMask(
        _ drawable: ClosedRange<CGFloat>,
        gaps: [ClosedRange<CGFloat>],
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            spanMask(drawable, height: height)
            ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                spanMask(gap, height: height)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }

    private var timelineStrokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: PlayerTimelineMetrics.trackThickness,
            lineCap: .round,
            lineJoin: .round
        )
    }
}

// A circular crown and small shoulder fillets make the arch meet the track
// tangentially, without the hard joins of a literal semicircle.
private struct PlayerTimelineCurve: Shape {
    let trackStart: CGFloat
    let trackEnd: CGFloat
    let handleCenter: CGFloat

    func path(in rect: CGRect) -> Path {
        let baseline = PlayerTimelineMetrics.baseline
        let arch = PlayerTimelineArchGeometry(centerX: handleCenter, baseline: baseline)

        var path = Path()
        path.move(to: CGPoint(x: min(trackStart, arch.startX), y: baseline))
        if trackStart < arch.startX {
            path.addLine(to: CGPoint(x: arch.startX, y: baseline))
        }
        arch.add(to: &path)
        if trackEnd > arch.endX {
            path.addLine(to: CGPoint(x: trackEnd, y: baseline))
        }
        return path
    }
}

private struct PlayerTimelineArchGeometry {
    let centerX: CGFloat
    let baseline: CGFloat

    private let crownRadius = PlayerTimelineMetrics.crownRadius
    private let shoulderRadius = PlayerTimelineMetrics.shoulderRadius

    private var shoulderOffset: CGFloat {
        sqrt(crownRadius * crownRadius + 2 * crownRadius * shoulderRadius)
    }

    private var tangencyAngle: CGFloat {
        atan2(shoulderRadius, shoulderOffset)
    }

    var startX: CGFloat { centerX - shoulderOffset }
    var endX: CGFloat { centerX + shoulderOffset }

    func add(to path: inout Path) {
        let leftShoulderCenter = CGPoint(x: startX, y: baseline - shoulderRadius)
        let crownCenter = CGPoint(x: centerX, y: baseline)
        let rightShoulderCenter = CGPoint(x: endX, y: baseline - shoulderRadius)

        addCircularArc(
            to: &path,
            center: leftShoulderCenter,
            radius: shoulderRadius,
            startAngle: .pi / 2,
            endAngle: tangencyAngle
        )
        // Splitting at the crown keeps every cubic span at or below 90 degrees.
        addCircularArc(
            to: &path,
            center: crownCenter,
            radius: crownRadius,
            startAngle: -.pi + tangencyAngle,
            endAngle: -.pi / 2
        )
        addCircularArc(
            to: &path,
            center: crownCenter,
            radius: crownRadius,
            startAngle: -.pi / 2,
            endAngle: -tangencyAngle
        )
        addCircularArc(
            to: &path,
            center: rightShoulderCenter,
            radius: shoulderRadius,
            startAngle: .pi - tangencyAngle,
            endAngle: .pi / 2
        )
    }

    private func addCircularArc(
        to path: inout Path,
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) {
        let sweep = endAngle - startAngle
        let controlScale = CGFloat(4.0 / 3.0) * CGFloat(tan(Double(sweep / 4)))
        let start = point(onCircleAt: startAngle, center: center, radius: radius)
        let end = point(onCircleAt: endAngle, center: center, radius: radius)
        let startTangent = CGPoint(x: -sin(startAngle), y: cos(startAngle))
        let endTangent = CGPoint(x: -sin(endAngle), y: cos(endAngle))

        path.addCurve(
            to: end,
            control1: CGPoint(
                x: start.x + controlScale * radius * startTangent.x,
                y: start.y + controlScale * radius * startTangent.y
            ),
            control2: CGPoint(
                x: end.x - controlScale * radius * endTangent.x,
                y: end.y - controlScale * radius * endTangent.y
            )
        )
    }

    private func point(onCircleAt angle: CGFloat, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }
}

#if !os(tvOS)
    private struct PlayerRaisedHumpTouchTimeline: View {
        @Binding var position: Double
        let duration: Double?
        let bufferedAhead: Double
        let playbackPosition: Double
        let marks: PlayerTimelineMarks
        let preview: Double?
        let onBegin: (Double) -> Void
        let onUpdate: (Double) -> Void
        let onFinish: () -> Void
        let onLayoutChanged: () -> Void

        private var displayPosition: Double {
            preview ?? PlayerTimelinePolicy.clampedPosition(position, duration: duration)
        }

        var body: some View {
            GeometryReader { proxy in
                let geometry = PlayerTimelineGeometry(
                    width: proxy.size.width,
                    duration: duration,
                    dotDiameter: PlayerTimelineMetrics.dotDiameter
                )
                let handleX = geometry.handleCenter(position: displayPosition)

                ZStack {
                    PlayerRaisedHumpTrack(
                        position: displayPosition,
                        duration: duration,
                        bufferedAhead: bufferedAhead,
                        playbackPosition: playbackPosition,
                        marks: marks,
                        isFocused: false
                    )

                    PlayerTimelineTouchBridge(
                        geometry: geometry,
                        handleCenterX: handleX,
                        controlHeight: PlayerTimelineMetrics.controlHeight,
                        enabled: PlayerTimelinePolicy.validDuration(duration) != nil,
                        onBegin: onBegin,
                        onUpdate: onUpdate,
                        onFinish: onFinish,
                        onLayoutChanged: onLayoutChanged
                    )
                    .frame(width: proxy.size.width, height: PlayerTimelineMetrics.controlHeight)
                    .allowsHitTesting(true)
                }
                .frame(width: proxy.size.width, height: PlayerTimelineMetrics.controlHeight)
                .contentShape([.interaction, .accessibility], Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "player.timeline.label", table: "Plinx"))
                .accessibilityValue(accessibilityValue)
                .accessibilityIdentifier("player.timeline")
                // The intentionally overhanging curve must not enlarge the AX
                // bounds beyond the actual interactive control row.
                .accessibilityAdjustableAction { direction in
                    let multiplier: Int = direction == .increment ? 1 : -1
                    guard let next = PlayerTimelinePolicy.accessibilityAdjustedPosition(
                        position: displayPosition,
                        duration: duration,
                        direction: multiplier
                    ) else { return }
                    onBegin(next)
                    onFinish()
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: PlayerTimelineMetrics.controlHeight,
                maxHeight: PlayerTimelineMetrics.controlHeight
            )
        }

        private var accessibilityValue: String {
            guard let duration = PlayerTimelinePolicy.validDuration(duration) else {
                return String(localized: "player.timeline.unavailable", table: "Plinx")
            }
            return String(
                localized: "player.timeline.value \(PlayerTimelinePolicy.formatTime(displayPosition)) \(PlayerTimelinePolicy.formatTime(duration))",
                table: "Plinx"
            )
        }
    }

    private struct PlayerTimelineTouchBridge: UIViewRepresentable {
        let geometry: PlayerTimelineGeometry
        let handleCenterX: CGFloat
        let controlHeight: CGFloat
        let enabled: Bool
        let onBegin: (Double) -> Void
        let onUpdate: (Double) -> Void
        let onFinish: () -> Void
        let onLayoutChanged: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(configuration: configuration)
        }

        func makeUIView(context: Context) -> TrackingView {
            let view = TrackingView()
            view.backgroundColor = .clear
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            pan.delegate = context.coordinator
            pan.cancelsTouchesInView = false
            view.addGestureRecognizer(pan)
            context.coordinator.view = view
            return view
        }

        func updateUIView(_ uiView: TrackingView, context: Context) {
            context.coordinator.update(configuration: configuration)
            uiView.isUserInteractionEnabled = enabled
        }

        static func dismantleUIView(_ uiView: TrackingView, coordinator: Coordinator) {
            coordinator.cancelForDismantle()
        }

        private var configuration: PlayerTimelineTouchConfiguration {
            PlayerTimelineTouchConfiguration(
                geometry: geometry,
                handleCenterX: handleCenterX,
                controlHeight: controlHeight,
                enabled: enabled,
                onBegin: onBegin,
                onUpdate: onUpdate,
                onFinish: onFinish,
                onLayoutChanged: onLayoutChanged
            )
        }

        final class TrackingView: UIView {}

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            weak var view: UIView?
            private var configuration: PlayerTimelineTouchConfiguration
            private var dragSession: PlayerTimelineDragSession?
            private var pendingInitialTouchX: CGFloat?
            private var didBeginEditing = false
            private var lastWidth: CGFloat?

            init(configuration: PlayerTimelineTouchConfiguration) {
                self.configuration = configuration
            }

            func update(configuration: PlayerTimelineTouchConfiguration) {
                if let lastWidth, abs(lastWidth - configuration.geometry.width) > 0.5, dragSession != nil {
                    endTracking(notify: true)
                    configuration.onLayoutChanged()
                }
                lastWidth = configuration.geometry.width
                self.configuration = configuration
            }

            func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
                guard configuration.enabled, let view else { return false }
                let location = touch.location(in: view)
                let receivesTouch = configuration.geometry.handleHitRect(
                    centerX: configuration.handleCenterX,
                    controlHeight: configuration.controlHeight
                ).contains(location)
                pendingInitialTouchX = receivesTouch ? location.x : nil
                return receivesTouch
            }

            @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
                guard let view else { return }
                let location = recognizer.location(in: view)

                switch recognizer.state {
                case .began:
                    dragSession = PlayerTimelineDragSession(
                        initialTouchX: pendingInitialTouchX ?? location.x,
                        handleCenterX: configuration.handleCenterX
                    )
                    didBeginEditing = false

                case .changed:
                    process(location: location)

                case .ended, .cancelled, .failed:
                    if recognizer.state == .ended { process(location: location) }
                    endTracking(notify: true)

                default:
                    break
                }
            }

            func cancelForDismantle() {
                endTracking(notify: true)
            }

            private func process(location: CGPoint) {
                guard let dragSession else { return }
                guard dragSession.shouldProcess(at: location.x, isEditing: didBeginEditing) else { return }
                guard let preview = dragSession.previewPosition(
                    at: location.x,
                    geometry: configuration.geometry
                ) else { return }

                if !didBeginEditing {
                    didBeginEditing = true
                    configuration.onBegin(preview)
                } else {
                    configuration.onUpdate(preview)
                }
            }

            private func endTracking(notify: Bool) {
                let shouldNotify = didBeginEditing && notify
                dragSession = nil
                pendingInitialTouchX = nil
                didBeginEditing = false
                if shouldNotify {
                    configuration.onFinish()
                }
            }
        }
    }

    private struct PlayerTimelineTouchConfiguration {
        let geometry: PlayerTimelineGeometry
        let handleCenterX: CGFloat
        let controlHeight: CGFloat
        let enabled: Bool
        let onBegin: (Double) -> Void
        let onUpdate: (Double) -> Void
        let onFinish: () -> Void
        let onLayoutChanged: () -> Void
    }
#endif

#if os(tvOS)
    /// Remote input: clickpad presses step through the video, faster on repeated presses; a swipe on the touch
    /// surface drags the playhead when `swipesScrub` allows it. The scrub commits a moment after the last input,
    /// or when focus leaves. Back during a scrub cancels it when the player supports cancelling.
    private struct PlayerRaisedHumpTVTimeline: View {
        @Binding var position: Double
        let duration: Double?
        let bufferedAhead: Double
        let playbackPosition: Double
        let marks: PlayerTimelineMarks
        let swipesScrub: Bool
        let onEditingChanged: (Bool) -> Void
        let onCancel: (() -> Void)?
        let onIdleSwipe: () -> Void

        @State private var consecutiveMoves = 0
        @State private var lifecycle = PlayerTimelineEditingLifecycle()
        @State private var commitWorkItem: DispatchWorkItem?
        @State private var commitGeneration = PlayerTimelineCommitGeneration()
        @State private var isSwiping = false
        @State private var panStartPosition: Double?
        @State private var lastPanEnd: Date?
        @FocusState private var isFocused: Bool
        @Environment(\.scenePhase) private var scenePhase

        private let scrubCommitDelay: TimeInterval = 0.4
        /// Share of the video a swipe across the whole touch surface covers.
        private let swipeSpan = 0.06
        /// A swipe can also reach the focus engine as move commands, which must not add steps to the drag.
        private let movesIgnoredAfterSwipe: TimeInterval = 0.3

        var body: some View {
            PlayerRaisedHumpTrack(
                position: PlayerTimelinePolicy.clampedPosition(position, duration: duration),
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: playbackPosition,
                marks: marks,
                isFocused: isFocused
            )
            .contentShape(Rectangle())
            .background {
                PlinxTimelineTouchSurfacePan(
                    isEnabled: isFocused,
                    onChanged: handlePan(translation:width:),
                    onEnded: endPan
                )
            }
            .focusable(PlayerTimelinePolicy.validDuration(duration) != nil)
            .focused($isFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                handleMove(direction)
            }
            .onExitCommand(perform: exitAction)
            .onChange(of: isFocused) { _, focused in
                if !focused { finishScrubbingIfNeeded() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active { finishScrubbingIfNeeded() }
            }
            .onChange(of: duration) { _, newDuration in
                guard PlayerTimelinePolicy.validDuration(newDuration) != nil else {
                    if lifecycle.isEditing { position = PlayerTimelinePolicy.finitePosition(playbackPosition) }
                    finishScrubbingIfNeeded()
                    return
                }
                position = PlayerTimelinePolicy.clampedPosition(position, duration: newDuration)
            }
            // Leaving without a choice (a prompt or panel replaced the controls) is not a commit.
            .onDisappear { cancelScrubbingIfNeeded() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "player.timeline.label", table: "Plinx"))
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("player.timeline")
            .accessibilityHidden(false)
            .accessibilityAdjustableAction { direction in
                let multiplier: Int = direction == .increment ? 1 : -1
                guard let next = PlayerTimelinePolicy.accessibilityAdjustedPosition(
                    position: position,
                    duration: duration,
                    direction: multiplier,
                    step: PlayerTimelinePolicy.tvScrubStep(duration: duration)
                ) else { return }
                startScrubbingIfNeeded()
                position = next
                scheduleCommit()
            }
        }

        private var accessibilityValue: String {
            guard let duration = PlayerTimelinePolicy.validDuration(duration) else {
                return String(localized: "player.timeline.unavailable", table: "Plinx")
            }
            return String(
                localized: "player.timeline.value \(PlayerTimelinePolicy.formatTime(position)) \(PlayerTimelinePolicy.formatTime(duration))",
                table: "Plinx"
            )
        }

        /// Back only belongs to the timeline during a scrub; otherwise it reaches the player.
        private var exitAction: (() -> Void)? {
            guard lifecycle.isEditing else { return nil }
            return { cancelScrubbingIfNeeded() }
        }

        private func handleMove(_ direction: MoveCommandDirection) {
            guard isFocused, let duration = PlayerTimelinePolicy.validDuration(duration) else { return }
            guard direction == .left || direction == .right else { return }
            if isSwiping { return }
            if let lastPanEnd, Date().timeIntervalSince(lastPanEnd) < movesIgnoredAfterSwipe { return }
            let nextMoveCount = consecutiveMoves + 1
            let delta = PlayerTimelinePolicy.tvDelta(duration: duration, consecutiveMoves: nextMoveCount)
            let signedDelta = direction == .left ? -delta : delta
            let current = PlayerTimelinePolicy.clampedPosition(position, duration: duration)
            let next = min(max(current + signedDelta, 0), duration)
            guard next != current else { return }
            startScrubbingIfNeeded()
            consecutiveMoves = nextMoveCount
            position = next
            scheduleCommit()
        }

        private func handlePan(translation: CGFloat, width: CGFloat) {
            guard isFocused, let duration = PlayerTimelinePolicy.validDuration(duration), width > 0 else { return }
            let isStart = !isSwiping
            isSwiping = true
            guard swipesScrub || lifecycle.isEditing else {
                if isStart { onIdleSwipe() }
                return
            }
            if panStartPosition == nil {
                startScrubbingIfNeeded()
                panStartPosition = PlayerTimelinePolicy.clampedPosition(position, duration: duration)
            }
            // The scrub stays open while the finger moves.
            holdCommit()
            guard let panStartPosition else { return }
            let offset = Double(translation / width) * duration * swipeSpan
            position = min(max(panStartPosition + offset, 0), duration)
        }

        private func endPan() {
            guard isSwiping else { return }
            isSwiping = false
            if panStartPosition == nil {
                onIdleSwipe()
            } else {
                scheduleCommit()
            }
            panStartPosition = nil
            lastPanEnd = Date()
        }

        private func startScrubbingIfNeeded() {
            if lifecycle.begin() { onEditingChanged(true) }
        }

        private func scheduleCommit() {
            let generation = commitGeneration.schedule()
            commitWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                guard commitGeneration.isCurrent(generation) else { return }
                finishScrubbingIfNeeded()
            }
            commitWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + scrubCommitDelay, execute: workItem)
        }

        private func holdCommit() {
            commitGeneration.invalidate()
            commitWorkItem?.cancel()
            commitWorkItem = nil
        }

        private func resetInput() {
            holdCommit()
            consecutiveMoves = 0
            panStartPosition = nil
        }

        private func finishScrubbingIfNeeded() {
            resetInput()
            if lifecycle.finish() { onEditingChanged(false) }
        }

        /// Without a cancel handler the scrub commits, so the player never stays in a scrub it cannot leave.
        private func cancelScrubbingIfNeeded() {
            resetInput()
            guard lifecycle.finish() else { return }
            if let onCancel {
                onCancel()
            } else {
                onEditingChanged(false)
            }
        }
    }

    /// Follows a finger on the Siri Remote touch surface while the timeline holds the focus, through a window-level
    /// recognizer (`PlinxTimelineTouchSurfacePanView`). Clickpad presses stay move commands.
    private struct PlinxTimelineTouchSurfacePan: UIViewRepresentable {
        var isEnabled: Bool
        var onChanged: (CGFloat, CGFloat) -> Void
        var onEnded: () -> Void

        func makeUIView(context _: Context) -> PlinxTimelineTouchSurfacePanView {
            PlinxTimelineTouchSurfacePanView()
        }

        func updateUIView(_ view: PlinxTimelineTouchSurfacePanView, context _: Context) {
            view.onChanged = onChanged
            view.onEnded = onEnded
            view.recognizer.isEnabled = isEnabled
        }

        static func dismantleUIView(_ view: PlinxTimelineTouchSurfacePanView, coordinator _: ()) {
            view.recognizer.view?.removeGestureRecognizer(view.recognizer)
        }
    }

    /// Touches reach the focused view's window, not the SwiftUI view, so the pan recognizer sits on the window.
    /// Ported from upstream Strimr's `PlayerTouchSurfacePanView` (tvOS `PlayerScrubInteraction.swift`), whose
    /// file left with the system player timeline; this timeline is its only user.
    private final class PlinxTimelineTouchSurfacePanView: UIView, UIGestureRecognizerDelegate {
        let recognizer = UIPanGestureRecognizer()
        var onChanged: (CGFloat, CGFloat) -> Void = { _, _ in }
        var onEnded: () -> Void = {}

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            recognizer.cancelsTouchesInView = false
            // Clickpad presses must reach the focused view right away, even while a finger rests on the surface.
            recognizer.allowedPressTypes = []
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handlePan(_:)))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                onChanged(recognizer.translation(in: recognizer.view).x, recognizer.view?.bounds.width ?? 0)
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
#endif
