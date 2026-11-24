import SwiftUI

/// Plinx's large, handle-first player timeline.
///
/// The public shape deliberately matches the paired Strimr timeline so both
/// iOS and tvOS player overlays can resolve this Plinx-owned implementation.
struct PlayerTimelineView: View {
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var playbackPosition: Double
    var onEditingChanged: (Bool) -> Void

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

    private var elapsedText: String {
        isAvailable ? PlayerTimelinePolicy.formatTime(displayPosition) : "--:--"
    }

    private var remainingText: String {
        guard let duration = PlayerTimelinePolicy.validDuration(duration) else { return "--:--" }
        return "-\(PlayerTimelinePolicy.formatTime(max(duration - displayPosition, 0)))"
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
            #if os(tvOS)
            PlayerRaisedHumpTVTimeline(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: playbackPosition,
                onEditingChanged: onEditingChanged
            )
            .accessibilityHint(String(localized: "player.timeline.tvHint", table: "Plinx"))
            #else
            PlayerRaisedHumpTouchTimeline(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: playbackPosition,
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

            HStack {
                Text(elapsedText)
                Spacer()
                Text(remainingText)
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        #if os(tvOS)
        .padding(.vertical, 8)
        #else
        .padding(.bottom, 8)
        #endif
    }

    #if !os(tvOS)
    private func beginTouchEditing(_ preview: Double) {
        guard isAvailable, touchLifecycle.begin() else { return }
        // The parent copies its authoritative playback position in this callback.
        // Set the preview only after it has done so, avoiding a first-drag jump.
        onEditingChanged(true)
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
        onEditingChanged(false)
    }
    #endif
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
    #else
    static let controlHeight = PlinxPlayerControlLayout.TouchTimeline.controlHeight
    static let trackThickness = PlinxPlayerControlLayout.TouchTimeline.trackThickness
    static let humpWidth: CGFloat = 56
    static let humpRise = PlinxPlayerControlLayout.TouchTimeline.humpRise
    static let crownRadius = PlinxPlayerControlLayout.TouchTimeline.humpRise
    static let shoulderRadius: CGFloat = 6
    static let dotDiameter: CGFloat = 12
    static let baseline = PlinxPlayerControlLayout.TouchTimeline.baseline
    #endif
}

private struct PlayerRaisedHumpTrack: View {
    let position: Double
    let duration: Double?
    let bufferedAhead: Double
    let playbackPosition: Double
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

            ZStack {
                ZStack {
                    PlayerTimelineCurve(
                        trackStart: geometry.trackStart,
                        trackEnd: geometry.trackEnd,
                        handleCenter: handleX
                    )
                    .stroke(Color.white.opacity(0.34), style: timelineStrokeStyle)

                    PlayerTimelineCurve(
                        trackStart: geometry.trackStart,
                        trackEnd: geometry.trackEnd,
                        handleCenter: handleX
                    )
                    .stroke(Color.white.opacity(0.63), style: timelineStrokeStyle)
                    .mask(alignment: .topLeading) {
                        spanMask(bufferedSpan, height: proxy.size.height)
                    }

                    PlayerTimelineCurve(
                        trackStart: geometry.trackStart,
                        trackEnd: geometry.trackEnd,
                        handleCenter: handleX
                    )
                    .stroke(Color.white, style: timelineStrokeStyle)
                    .mask(alignment: .topLeading) {
                        spanMask(playedSpan, height: proxy.size.height)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 7, x: 0, y: 4)
                }
                // The hump may overhang the track ends so it is never cut in
                // half at the start or end of the video.
                .mask(alignment: .topLeading) {
                    spanMask(drawableSpan, height: proxy.size.height)
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
        .frame(maxWidth: .infinity, minHeight: PlayerTimelineMetrics.controlHeight, maxHeight: PlayerTimelineMetrics.controlHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A full-height rectangle covering `span` in the track's coordinates.
    private func spanMask(_ span: ClosedRange<CGFloat>, height: CGFloat) -> some View {
        Rectangle()
            .frame(width: max(span.upperBound - span.lowerBound, 0), height: height)
            .offset(x: span.lowerBound)
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
        .frame(maxWidth: .infinity, minHeight: PlayerTimelineMetrics.controlHeight, maxHeight: PlayerTimelineMetrics.controlHeight)
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

import UIKit

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
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
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
            guard let preview = dragSession.previewPosition(at: location.x, geometry: configuration.geometry) else { return }

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
private struct PlayerRaisedHumpTVTimeline: View {
    @Binding var position: Double
    let duration: Double?
    let bufferedAhead: Double
    let playbackPosition: Double
    let onEditingChanged: (Bool) -> Void

    @State private var consecutiveMoves = 0
    @State private var lifecycle = PlayerTimelineEditingLifecycle()
    @State private var commitWorkItem: DispatchWorkItem?
    @State private var commitGeneration = PlayerTimelineCommitGeneration()
    @FocusState private var isFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private let scrubCommitDelay: TimeInterval = 0.4

    var body: some View {
        PlayerRaisedHumpTrack(
            position: PlayerTimelinePolicy.clampedPosition(position, duration: duration),
            duration: duration,
            bufferedAhead: bufferedAhead,
            playbackPosition: playbackPosition,
            isFocused: isFocused
        )
        .contentShape(Rectangle())
        .focusable(PlayerTimelinePolicy.validDuration(duration) != nil)
        .focused($isFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            guard isFocused, let duration = PlayerTimelinePolicy.validDuration(duration) else { return }
            switch direction {
            case .left, .right:
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
            default:
                break
            }
        }
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
        .onDisappear { finishScrubbingIfNeeded() }
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

    private func finishScrubbingIfNeeded() {
        commitGeneration.invalidate()
        commitWorkItem?.cancel()
        commitWorkItem = nil
        consecutiveMoves = 0
        if lifecycle.finish() { onEditingChanged(false) }
    }
}
#endif
