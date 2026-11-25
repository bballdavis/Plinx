import SwiftUI

/// The iOS player controls with Plinx chrome, built by `PlayerView` with the
/// upstream parameter list.
///
/// Layout: a header (back, title, then sleep timer, Picture in Picture,
/// tracks, video fill, More Actions and settings), the auxiliary row (touch
/// lock, playback badges, skip button) sitting in the timeline's headroom, the
/// raised-hump timeline, and the transport buttons in the middle. The touch
/// lock hides everything but itself, in place, so it stays under the finger.
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
    var showsEndsAtTime: Bool
    var isScrubbing: Bool
    var onDismiss: () -> Void
    var tracksMenu: PlayerTracksMenuModel
    var tracksMenuActions: PlayerTracksMenuActions
    var onShowSettings: () -> Void
    var chapters: [MediaChapter]
    var showsChaptersOnTimeline: Bool
    var skipSegments: [SkipSegment]
    var scrubPreview: PlayerScrubPreview?
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var onScrubbingChanged: (Bool) -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var isLocked: Bool
    var onToggleLock: () -> Void
    var isSharePlay: Bool
    var showsPictureInPicture: Bool
    var isPictureInPictureEnabled: Bool
    var onStartPictureInPicture: () -> Void
    var hasInfoPanel: Bool
    var onShowInfoPanel: () -> Void
    var isLive: Bool
    var behindLiveSeconds: Double
    var isAtLiveEdge: Bool
    var lastLiveChannel: LiveTVChannel?
    var onGoLive: () -> Void
    var onShowLiveChannels: () -> Void
    var onLastLiveChannel: () -> Void
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
    var onPreviousChannel: () -> Void
    var onNextChannel: () -> Void
    var sleepTimer: SleepTimer?
    var onTitleInteractionChanged: (Bool) -> Void = { _ in }

    private var playbackBadges: [PlinxPlayerControlBadge] {
        var badges: [PlinxPlayerControlBadge] = []

        if let videoResolution {
            badges.append(
                PlinxPlayerControlBadge(
                    id: "resolution",
                    title: videoResolution,
                    systemImage: nil
                )
            )
        }

        if let videoFormatBadge {
            badges.append(
                PlinxPlayerControlBadge(
                    id: videoFormatBadge.id,
                    title: videoFormatBadge.title,
                    systemImage: "sparkles"
                )
            )
        }

        return badges
    }

    /// Subtitle search downloads from the server, which is a parent-only action: kids never see it.
    private var kidSafeTracksMenu: PlayerTracksMenuModel {
        var model = tracksMenu
        model.canSearchSubtitles = model.canSearchSubtitles && ContentSafetyGate.shared.isParentUnlocked
        return model
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
                    PlinxPlayerControlsHeader(
                        media: media,
                        onDismiss: onDismiss,
                        tracksMenu: kidSafeTracksMenu,
                        tracksMenuActions: tracksMenuActions,
                        onShowSettings: onShowSettings,
                        sleepTimer: sleepTimer,
                        isSharePlay: isSharePlay,
                        showsPictureInPicture: showsPictureInPicture,
                        isPictureInPictureEnabled: isPictureInPictureEnabled,
                        onStartPictureInPicture: onStartPictureInPicture,
                        onTitleInteractionChanged: onTitleInteractionChanged,
                        containerSize: chromeSize
                    )
                    .hiddenWhenControlsLocked(isLocked)

                    Spacer(minLength: 0)

                    VStack(spacing: insets.auxiliaryRowSpacing) {
                        PlinxPlayerAuxiliaryControlsRow(
                            isLocked: isLocked,
                            onToggleLock: onToggleLock,
                            skipMarkerTitle: skipMarkerTitle,
                            onSkipMarker: onSkipMarker,
                            badges: playbackBadges
                        )
                        .padding(.horizontal, 24)
                        .opacity(isScrubbing ? 0 : 1)
                        .allowsHitTesting(!isScrubbing)
                        // Drawn above the timeline's empty touch headroom.
                        .zIndex(1)

                        timelineRow
                            .hiddenWhenControlsLocked(isLocked)
                    }
                }
                .padding(.horizontal, insets.horizontal)
                .padding(.vertical, insets.vertical)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                PlinxPlayerPrimaryControls(
                    isPaused: isPaused,
                    onSeekBackward: onSeekBackward,
                    onPlayPause: onPlayPause,
                    onSeekForward: onSeekForward,
                    seekBackwardSeconds: seekBackwardSeconds,
                    seekForwardSeconds: seekForwardSeconds,
                    isLive: isLive,
                    canSwitchPreviousChannel: canSwitchPreviousChannel,
                    canSwitchNextChannel: canSwitchNextChannel,
                    onPreviousChannel: onPreviousChannel,
                    onNextChannel: onNextChannel
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresSafeArea(.container)
                .hiddenWhenControlsLocked(isLocked)
            }
            .background {
                PlayerControlsBackground()
                    .hiddenWhenControlsLocked(isLocked)
            }
            .frame(width: chromeSize.width, height: chromeSize.height)
            .offset(x: -reclaimed.leading)
        }
    }

    @ViewBuilder
    private var timelineRow: some View {
        if isLive {
            LiveTVPlayerStatusRow(
                behindLiveSeconds: behindLiveSeconds,
                isAtLiveEdge: isAtLiveEdge,
                onGoLive: onGoLive,
                lastChannel: lastLiveChannel,
                onShowChannels: onShowLiveChannels,
                onLastChannel: onLastLiveChannel
            )
            .controlSize(.small)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        } else {
            PlayerTimelineView(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: bufferBasePosition,
                showsEndsAtTime: showsEndsAtTime,
                chapters: chapters,
                showsChaptersOnTimeline: showsChaptersOnTimeline,
                skipSegments: skipSegments,
                scrubPreview: scrubPreview,
                onEditingChanged: onScrubbingChanged,
                // The preview grows upward over the hidden auxiliary row, so the
                // track never moves under the finger.
                floatsScrubDetails: true
            )
            .accessibilityIdentifier("player.timeline")
            .overlay(alignment: .bottom) {
                if hasInfoPanel {
                    PlayerInfoPanelDisclosureButton(action: onShowInfoPanel)
                        .opacity(isScrubbing ? 0 : 1)
                        .allowsHitTesting(!isScrubbing)
                        .offset(y: 14)
                }
            }
        }
    }
}

private extension View {
    /// Keeps the hidden controls in the layout, so the lock button stays exactly where it was pressed.
    func hiddenWhenControlsLocked(_ isLocked: Bool) -> some View {
        opacity(isLocked ? 0 : 1)
            .allowsHitTesting(!isLocked)
            .accessibilityHidden(isLocked)
    }
}

private struct PlinxPlayerControlBadge: Identifiable {
    var id: String
    var title: String
    var systemImage: String?
}

private struct PlinxPlayerAuxiliaryControlsRow: View {
    var isLocked: Bool
    var onToggleLock: () -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var badges: [PlinxPlayerControlBadge]

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ControlsLockButton(isLocked: isLocked, action: onToggleLock)

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
            .hiddenWhenControlsLocked(isLocked)
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

private struct PlinxPlayerControlsHeader: View {
    @Environment(\.plinxVideoFill) private var videoFill
    @Environment(\.plinxPlayerMoreActions) private var moreActions
    var media: MediaItem?
    var onDismiss: () -> Void
    var tracksMenu: PlayerTracksMenuModel
    var tracksMenuActions: PlayerTracksMenuActions
    var onShowSettings: () -> Void
    var sleepTimer: SleepTimer?
    var isSharePlay: Bool
    var showsPictureInPicture: Bool
    var isPictureInPictureEnabled: Bool
    var onStartPictureInPicture: () -> Void
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
                            subtitle: media?.episodeTitleLabel,
                            presentation: presentation,
                            isSharePlay: isSharePlay,
                            onInteractionChanged: onTitleInteractionChanged
                        )
                    }
                    sleepTimerBadge
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    dismissButton
                    Spacer(minLength: 12)
                    if let title = media?.primaryLabel {
                        PlinxPlayerTitleView(
                            title: title,
                            subtitle: media?.episodeTitleLabel,
                            presentation: presentation,
                            isSharePlay: isSharePlay,
                            onInteractionChanged: onTitleInteractionChanged
                        )
                        .frame(maxWidth: PlinxPlayerControlLayout.titleMaxWidth(
                            width: containerSize.width - trailingAllowance,
                            presentation: presentation
                        ))
                    }
                    Spacer(minLength: 12)
                    sleepTimerBadge
                    trailingButtons(includesPictureInPicture: true)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(minHeight: PlinxPlayerControlLayout.headerButtonSize + 16)
    }

    /// Room taken by the header buttons that `titleMaxWidth` does not already reserve (it reserves back, More
    /// Actions and settings), so the title never pushes a button off screen.
    private var trailingAllowance: CGFloat {
        let buttonSlot = PlinxPlayerControlLayout.headerButtonSize + 12
        let extraButtons = [true, videoFill != nil, showsPictureInPicture]
            .filter { $0 }
            .count
        return CGFloat(extraButtons) * buttonSlot
    }

    @ViewBuilder
    private var sleepTimerBadge: some View {
        if let sleepTimer, sleepTimer.isActive {
            Button(action: onShowSettings) {
                SleepTimerBadge(sleepTimer: sleepTimer, mediaKind: media?.type)
            }
            .buttonStyle(.plain)
        }
    }

    /// Compact portrait: a phone's width holds back plus four header buttons, so Picture in Picture is offered in
    /// landscape and on wider screens only.
    private var buttonRow: some View {
        HStack {
            dismissButton
            Spacer()
            trailingButtons(includesPictureInPicture: false)
        }
    }

    private func trailingButtons(includesPictureInPicture: Bool) -> some View {
        HStack(spacing: 12) {
            if includesPictureInPicture, showsPictureInPicture {
                PlayerPictureInPictureButton(action: onStartPictureInPicture)
                    .disabled(!isPictureInPictureEnabled)
                    .opacity(isPictureInPictureEnabled ? 1 : 0.5)
            }
            PlayerTracksMenuButton(model: tracksMenu, actions: tracksMenuActions)
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
                .accessibilityLabel(Text(
                    videoFill.wrappedValue ? "player.video.fit.action" : "player.video.fill.action",
                    tableName: "Plinx"
                ))
                .accessibilityValue(Text(
                    videoFill.wrappedValue ? "player.video.fill" : "player.video.fit",
                    tableName: "Plinx"
                ))
                .accessibilityHint(Text("player.video.fill.hint", tableName: "Plinx"))
            }
            if let moreActions, let media {
                PlayerMoreActionsButton { moreActions(media) }
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
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.actions.back", table: "Plinx"))
        .accessibilityIdentifier("player.back")
    }
}

private struct PlinxPlayerPrimaryControls: View {
    var isPaused: Bool
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var isLive: Bool
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
    var onPreviousChannel: () -> Void
    var onNextChannel: () -> Void

    var body: some View {
        Group {
            if isLive {
                ZStack {
                    HStack {
                        PlinxPlayerSeekButton(
                            systemName: "chevron.left",
                            accessibilityLabel: String(localized: "livetv.player.previousChannel"),
                            action: onPreviousChannel
                        )
                        .disabled(!canSwitchPreviousChannel)

                        Spacer()

                        PlinxPlayerSeekButton(
                            systemName: "chevron.right",
                            accessibilityLabel: String(localized: "livetv.player.nextChannel"),
                            action: onNextChannel
                        )
                        .disabled(!canSwitchNextChannel)
                    }

                    transportControls
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
            } else {
                transportControls
            }
        }
        .padding(.bottom, 4)
    }

    private var transportControls: some View {
        HStack(spacing: 26) {
            PlinxPlayerSeekButton(
                systemName: iconName(prefix: "gobackward", seconds: seekBackwardSeconds),
                accessibilityLabel: String(
                    localized: "player.controls.rewindSeconds \(seekBackwardSeconds)"
                ),
                action: onSeekBackward
            )

            PlinxPlayPauseButton(isPaused: isPaused, action: onPlayPause)
                .accessibilityIdentifier("player.playPause")

            PlinxPlayerSeekButton(
                systemName: iconName(prefix: "goforward", seconds: seekForwardSeconds),
                accessibilityLabel: String(
                    localized: "player.controls.skipForwardSeconds \(seekForwardSeconds)"
                ),
                action: onSeekForward
            )
        }
    }

    private func iconName(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}
