import SwiftUI

/// Plinx-owned player overlay presentation around Strimr's control actions.
struct PlayerControlsView: View {
    var media: MediaItem?
    var isPaused: Bool
    var isBuffering: Bool
    var videoResolution: String?
    var videoFormatBadge: PlayerVideoFormatBadge?
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var isScrubbing: Bool
    var onDismiss: () -> Void
    var onShowSettings: () -> Void
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var onScrubbingChanged: (Bool) -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var isRotationLocked: Bool
    var onToggleRotationLock: () -> Void
    var isSharePlay: Bool
    var onTitleInteractionChanged: (Bool) -> Void = { _ in }

    private var playbackBadges: [PlayerControlBadge] {
        var badges: [PlayerControlBadge] = []

        if let videoResolution {
            badges.append(
                PlayerControlBadge(
                    id: "resolution",
                    title: videoResolution,
                    systemImage: nil
                )
            )
        }

        if let videoFormatBadge {
            badges.append(
                PlayerControlBadge(
                    id: videoFormatBadge.id,
                    title: videoFormatBadge.title,
                    systemImage: "sparkles"
                )
            )
        }

        return badges
    }

    var body: some View {
        GeometryReader { container in
            let reclaimed = PlinxPlayerControlLayout.reclaimedStatusInsets(
                size: container.size,
                safeArea: container.safeAreaInsets
            )
            let chromeSize = CGSize(
                width: container.size.width + reclaimed.leading + reclaimed.trailing,
                height: container.size.height
            )
            let insets = PlinxPlayerControlLayout.chromeInsets(
                width: chromeSize.width,
                height: chromeSize.height
            )
            ZStack {
                VStack(spacing: 0) {
                    PlayerControlsHeader(
                        media: media,
                        onDismiss: onDismiss,
                        onShowSettings: onShowSettings,
                        isSharePlay: isSharePlay,
                        onTitleInteractionChanged: onTitleInteractionChanged,
                        containerSize: chromeSize
                    )

                    Spacer(minLength: 0)

                    VStack(spacing: insets.auxiliaryRowSpacing) {
                        PlayerAuxiliaryControlsRow(
                            isRotationLocked: isRotationLocked,
                            onToggleRotationLock: onToggleRotationLock,
                            skipMarkerTitle: skipMarkerTitle,
                            onSkipMarker: onSkipMarker,
                            badges: playbackBadges
                        )
                        .padding(.horizontal, 24)
                        .opacity(isScrubbing ? 0 : 1)
                        .allowsHitTesting(!isScrubbing)
                        // Drawn above the timeline's empty touch headroom.
                        .zIndex(1)

                        PlayerTimelineView(
                            position: $position,
                            duration: duration,
                            bufferedAhead: bufferedAhead,
                            playbackPosition: bufferBasePosition,
                            onEditingChanged: onScrubbingChanged
                        )
                        .accessibilityIdentifier("player.timeline")
                    }
                }
                .padding(.horizontal, insets.horizontal)
                .padding(.vertical, insets.vertical)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                PrimaryControls(
                    isPaused: isPaused,
                    onSeekBackward: onSeekBackward,
                    onPlayPause: onPlayPause,
                    onSeekForward: onSeekForward,
                    seekBackwardSeconds: seekBackwardSeconds,
                    seekForwardSeconds: seekForwardSeconds
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresSafeArea(.container)
            }
            .background {
                PlayerControlsBackground()
            }
            .frame(width: chromeSize.width, height: chromeSize.height)
            .offset(x: -reclaimed.leading)
        }
    }
}

private struct PlayerControlBadge: Identifiable {
    var id: String
    var title: String
    var systemImage: String?
}

private struct PlayerAuxiliaryControlsRow: View {
    var isRotationLocked: Bool
    var onToggleRotationLock: () -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var badges: [PlayerControlBadge]

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            RotationLockButton(isLocked: isRotationLocked, action: onToggleRotationLock)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                if hasSkipMarker {
                    if !badges.isEmpty {
                        badgesRow
                    }
                    if let skipMarkerTitle, let onSkipMarker {
                        SkipMarkerButton(title: skipMarkerTitle, action: onSkipMarker)
                    }
                } else if !badges.isEmpty {
                    badgesRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var hasSkipMarker: Bool {
        skipMarkerTitle != nil && onSkipMarker != nil
    }

    private var badgesRow: some View {
        HStack(spacing: 8) {
            ForEach(badges) { badge in
                PlayerBadge(badge.title, systemImage: badge.systemImage)
            }
        }
    }
}

private struct PlayerControlsHeader: View {
    @Environment(\.plinxVideoFill) private var videoFill
    @Environment(\.plinxPlayerMoreActions) private var moreActions
    var media: MediaItem?
    var onDismiss: () -> Void
    var onShowSettings: () -> Void
    var isSharePlay: Bool
    var onTitleInteractionChanged: (Bool) -> Void
    var containerSize: CGSize

    @ScaledMetric(relativeTo: .headline) private var iconSize =
        PlinxPlayerControlLayout.headerIconSize

    var body: some View {
        let presentation = PlinxPlayerControlLayout.headerPresentation(
            width: containerSize.width,
            height: containerSize.height
        )
        Group {
            if presentation == .compactPortrait {
                VStack(alignment: .leading, spacing: 8) {
                    buttonRow
                    if let title = media?.primaryLabel {
                        PlinxPlayerTitleView(
                            title: title,
                            subtitle: media?.tertiaryLabel,
                            presentation: presentation,
                            isSharePlay: isSharePlay,
                            onInteractionChanged: onTitleInteractionChanged
                        )
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    dismissButton
                    Spacer(minLength: 12)
                    if let title = media?.primaryLabel {
                        PlinxPlayerTitleView(
                            title: title,
                            subtitle: media?.tertiaryLabel,
                            presentation: presentation,
                            isSharePlay: isSharePlay,
                            onInteractionChanged: onTitleInteractionChanged
                        )
                        .frame(maxWidth: PlinxPlayerControlLayout.titleMaxWidth(
                            width: containerSize.width - (videoFill == nil ? 0 : 75),
                            presentation: presentation
                        ))
                    }
                    Spacer(minLength: 12)
                    trailingButtons
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(minHeight: PlinxPlayerControlLayout.headerButtonSize + 16)
    }

    private var buttonRow: some View {
        HStack {
            dismissButton
            Spacer()
            trailingButtons
        }
    }

    private var trailingButtons: some View {
        HStack(spacing: 12) {
            if let videoFill {
                Button {
                    onTitleInteractionChanged(true)
                    videoFill.wrappedValue.toggle()
                    onTitleInteractionChanged(false)
                } label: {
                    Image(systemName: videoFill.wrappedValue
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: iconSize, weight: .semibold))
                        .playerHeaderButtonChrome(isActive: videoFill.wrappedValue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("player.videoFit")
                .accessibilityLabel(Text(videoFill.wrappedValue ? "player.video.fit.action" : "player.video.fill.action", tableName: "Plinx"))
                .accessibilityValue(Text(videoFill.wrappedValue ? "player.video.fill" : "player.video.fit", tableName: "Plinx"))
                .accessibilityHint(Text("player.video.fill.hint", tableName: "Plinx"))
            }
            if let moreActions {
                PlayerMoreActionsButton(action: moreActions)
            }
            PlayerSettingsButton(action: onShowSettings)
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "chevron.backward")
                .font(.system(size: iconSize, weight: .semibold))
                .playerHeaderButtonChrome()
        }
        .accessibilityLabel(String(localized: "common.actions.back", table: "Plinx"))
        .accessibilityIdentifier("player.back")
    }
}

private struct PrimaryControls: View {
    var isPaused: Bool
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int

    var body: some View {
        HStack(spacing: 26) {
            PlayerIconButton(
                systemName: iconName(prefix: "gobackward", seconds: seekBackwardSeconds),
                accessibilityLabel: String(
                    localized: "player.controls.rewindSeconds \(seekBackwardSeconds)"
                ),
                action: onSeekBackward
            )

            PlayPauseButton(isPaused: isPaused, action: onPlayPause)
                .accessibilityIdentifier("player.playPause")

            PlayerIconButton(
                systemName: iconName(prefix: "goforward", seconds: seekForwardSeconds),
                accessibilityLabel: String(
                    localized: "player.controls.skipForwardSeconds \(seekForwardSeconds)"
                ),
                action: onSeekForward
            )
        }
        .padding(.bottom, 4)
    }

    private func iconName(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

private struct PlayerControlsBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(0.55),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)

            Spacer()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
