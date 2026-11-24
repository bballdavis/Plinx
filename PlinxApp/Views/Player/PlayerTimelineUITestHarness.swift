import SwiftUI

/// Deterministic fixture reached only through the existing --ui-testing route.
/// Uses the production timeline and the same begin/reset/commit binding order
/// as the upstream player, without requiring a Plex session or playback engine.
struct PlayerTimelineUITestHarness: View {
    @State private var position: Double
    @State private var playbackPosition: Double
    @State private var begins = 0
    @State private var commits = 0
    @State private var isScrubbing = false
    @State private var showsTimeline = true
    private let duration: Double?
    private let fullOverlay: Bool

    init() {
        let environment = ProcessInfo.processInfo.environment
        let initial = Double(environment["PLINX_TIMELINE_POSITION"] ?? "50") ?? 50
        _position = State(initialValue: initial)
        _playbackPosition = State(initialValue: initial)
        duration = environment["PLINX_TIMELINE_UNAVAILABLE"] == "1" ? nil : 100
        fullOverlay = environment["PLINX_TIMELINE_OVERLAY"] == "1"
    }

    var body: some View {
        if fullOverlay {
            controls
                .background(Color.black.ignoresSafeArea())
        } else {
            isolatedTimeline
        }
    }

    private var isolatedTimeline: some View {
        VStack(spacing: 24) {
            Text("Player timeline")
                .font(.title)
            HStack(spacing: 20) {
                metric("Position", value: String(format: "%.2f", position), id: "position")
                metric("Begins", value: String(begins), id: "begins")
                metric("Commits", value: String(commits), id: "commits")
                metric("Scrubbing", value: isScrubbing ? "yes" : "no", id: "scrubbing")
            }
            Spacer()
            if showsTimeline {
                PlayerTimelineView(
                    position: $position,
                    duration: duration,
                    bufferedAhead: 15,
                    playbackPosition: playbackPosition,
                    onEditingChanged: editingChanged
                )
            }
            Button("Hide timeline") {
                showsTimeline.toggle()
            }
            .accessibilityIdentifier("timeline.fixture.hide")
        }
        .padding(40)
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder
    private var controls: some View {
        #if os(tvOS)
        PlayerControlsTVView(
            media: nil, isPaused: true, videoResolution: "4K", videoFormatBadge: nil,
            position: $position, duration: duration, bufferedAhead: 15,
            bufferBasePosition: playbackPosition, isScrubbing: isScrubbing,
            onShowAudioSettings: {}, onShowSubtitleSettings: {},
            onSeekBackward: {}, onPlayPause: {}, onSeekForward: {},
            seekBackwardSeconds: 10, seekForwardSeconds: 30,
            onScrubbingChanged: editingChanged, skipMarkerTitle: "Skip Intro",
            onSkipMarker: {}, onUserInteraction: {}, isSharePlay: false
        )
        #else
        PlayerControlsView(
            media: nil, isPaused: true, isBuffering: false,
            videoResolution: "4K", videoFormatBadge: nil,
            position: $position, duration: duration, bufferedAhead: 15,
            bufferBasePosition: playbackPosition, isScrubbing: isScrubbing,
            onDismiss: {}, onShowSettings: {}, onSeekBackward: {},
            onPlayPause: {}, onSeekForward: {}, seekBackwardSeconds: 10,
            seekForwardSeconds: 30, onScrubbingChanged: editingChanged,
            skipMarkerTitle: "Skip Intro", onSkipMarker: {}, isRotationLocked: false,
            onToggleRotationLock: {}, isSharePlay: false
        )
        #endif
    }

    private func editingChanged(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            begins += 1
            position = playbackPosition
        } else {
            commits += 1
            playbackPosition = position
        }
    }

    private func metric(_ name: String, value: String, id: String) -> some View {
        Text("\(name): \(value)")
            .font(.caption.monospacedDigit())
            .accessibilityLabel(name)
            .accessibilityValue(value)
            .accessibilityIdentifier("timeline.fixture.\(id)")
    }
}
