#if os(tvOS)
import PlinxUI
import SwiftUI

/// The audio and subtitle panels of the tvOS player, with Plinx rows.
///
/// Takes the upstream parameters `PlayerView` passes: the tracks, the Off row
/// for subtitles, reset, sync, audio enhancements and subtitle appearance.
/// Subtitle search downloads from the server, which is a parent-only action,
/// so it is offered only while the parental gate is unlocked. The panel that
/// hosts this view handles Back; `onClose` is for standalone use.
struct PlayerTrackSelectionView: View {
    var titleKey: LocalizedStringKey
    var tracks: [PlaybackSettingsTrack]
    var selectedTrackID: Int?
    var showOffOption: Bool
    var onSelect: (Int?) -> Void
    var onSearchSubtitles: (() -> Void)?
    var onResetTrackSelections: (() -> Void)?
    var syncItem: PlaybackOffsetMenuItem?
    var onSelectSync: (PlaybackOffsetKind) -> Void = { _ in }
    var audioEnhancements: PlayerAudioEnhancements?
    var subtitleAppearance: SubtitleAppearanceAvailability?
    var onShowSubtitleAppearance: () -> Void = {}
    var initialOptionID: String?
    var onClose: (() -> Void)?

    @FocusState private var focusedOptionID: String?

    private var initialFocusID: String? {
        let options = options
        if let initialOptionID, options.contains(where: { $0.id == initialOptionID }) {
            return initialOptionID
        }
        return options.first(where: \.isSelected)?.id ?? options.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(titleKey)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("player.trackSelection")

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if tracks.isEmpty, !showOffOption {
                            Text("player.settings.audio.empty")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.68))
                                .padding(.vertical, 12)
                        }

                        ForEach(options) { option in
                            if let sectionTitle = option.sectionTitle {
                                Text(sectionTitle)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .padding(.top, 18)
                                    .padding(.horizontal, 8)
                            }
                            row(option)
                                .id(option.id)
                        }
                    }
                    // Room for the focused row's lift inside the scroll view's clipping.
                    .padding(10)
                }
                .onAppear {
                    guard let initialFocusID else { return }
                    proxy.scrollTo(initialFocusID, anchor: .center)
                    DispatchQueue.main.async { focusedOptionID = initialFocusID }
                }
            }
        }
        .padding(.vertical, 28)
        .onExitCommand(perform: onClose)
    }

    private var options: [PlayerTrackOption] {
        var result: [PlayerTrackOption] = []
        if showOffOption {
            result.append(PlayerTrackOption(
                id: "off",
                accessibilityKey: "off",
                title: String(localized: "player.settings.subtitles.off"),
                subtitle: String(localized: "player.settings.subtitles.offDescription"),
                isSelected: selectedTrackID == nil,
                action: { onSelect(nil) }
            ))
        }
        result += tracks.map { track in
            PlayerTrackOption(
                id: String(track.id),
                accessibilityKey: "track-\(track.id)",
                title: track.title,
                subtitle: track.subtitle,
                isSelected: selectedTrackID == track.id,
                action: { onSelect(track.track.id) }
            )
        }
        if let onSearchSubtitles, ContentSafetyGate.shared.isParentUnlocked {
            result.append(PlayerTrackOption(
                id: "search",
                accessibilityKey: "search",
                title: String(localized: "subtitles.search.action"),
                systemImage: "magnifyingglass",
                action: onSearchSubtitles
            ))
        }
        if let onResetTrackSelections {
            result.append(PlayerTrackOption(
                id: "reset",
                accessibilityKey: "reset",
                title: String(localized: "player.settings.tracks.reset"),
                systemImage: "arrow.counterclockwise",
                action: onResetTrackSelections
            ))
        }
        if let syncItem {
            result.append(PlayerTrackOption(
                id: "sync",
                accessibilityKey: "sync",
                title: syncItem.kind.title,
                subtitle: syncItem.availability.message ?? syncItem.value,
                highlightsSubtitle: syncItem.isActive && syncItem.availability.isAvailable,
                systemImage: syncItem.kind.systemImage,
                isDisabled: !syncItem.availability.isAvailable,
                opensSubmenu: true,
                sectionTitle: String(localized: "player.settings.sync"),
                action: { onSelectSync(syncItem.kind) }
            ))
        }
        if let audioEnhancements {
            result += audioEnhancements.options
        }
        if let subtitleAppearance {
            result.append(PlayerTrackOption(
                id: "subtitleAppearance",
                accessibilityKey: "subtitleAppearance",
                title: String(localized: "player.settings.subtitles.appearance"),
                subtitle: subtitleAppearance.message,
                systemImage: "textformat.size",
                isDisabled: !subtitleAppearance.isAvailable,
                opensSubmenu: true,
                action: onShowSubtitleAppearance
            ))
        }
        return result
    }

    private func row(_ option: PlayerTrackOption) -> some View {
        Button(action: option.action) {
            HStack(spacing: 18) {
                if let systemImage = option.systemImage, !option.isSelected {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(option.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    if let subtitle = option.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout.weight(option.highlightsSubtitle ? .semibold : .regular))
                            .foregroundStyle(
                                option.highlightsSubtitle
                                    ? Color.accentColor
                                    : .white.opacity(0.62)
                            )
                    }
                }

                Spacer(minLength: 0)

                if option.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else if option.opensSubmenu {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        option.isSelected
                            ? Color.accentColor.opacity(0.14)
                            : PlinxBrand.surface.opacity(0.92)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        option.isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: option.isSelected ? 1.5 : 1
                    )
            )
        }
        .focused($focusedOptionID, equals: option.id)
        .plinxTVFocusButton(
            isSelected: option.isSelected,
            style: PlinxFocusSurfaceStyle(
                selectionOpacity: 0.62,
                focusedScale: 1,
                focusedShadowRadius: 16,
                cornerRadius: 20,
                focusedFillOpacity: 0.1
            )
        )
        .disabled(option.isDisabled)
        .opacity(option.isDisabled ? 0.45 : 1)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
        .accessibilityIdentifier("player.track.\(option.accessibilityKey)")
        .accessibilityValue(option.isSelected ? "selectedPlinxTrack" : "PlinxTrack")
    }
}

/// One row of a track panel. `id` is the focus identity the player restores when it returns from a submenu.
struct PlayerTrackOption: Identifiable {
    let id: String
    let accessibilityKey: String
    let title: String
    var subtitle: String?
    var highlightsSubtitle = false
    var isSelected = false
    var systemImage: String?
    var isDisabled = false
    var opensSubmenu = false
    var sectionTitle: String?
    let action: () -> Void
}

/// Night mode and dialogue boost, offered at the end of the audio panel.
struct PlayerAudioEnhancements {
    var nightMode: Bool
    var dialogueBoost: DialogueBoost
    var isAvailable: Bool
    var onToggleNightMode: () -> Void
    var onShowDialogueBoost: () -> Void

    fileprivate var options: [PlayerTrackOption] {
        let unavailableMessage = isAvailable
            ? nil
            : String(localized: "player.settings.audioEnhancements.unavailable")
        return [
            PlayerTrackOption(
                id: "nightMode",
                accessibilityKey: "nightMode",
                title: String(localized: "settings.playback.nightMode"),
                subtitle: unavailableMessage,
                isSelected: nightMode,
                systemImage: "moon.stars",
                sectionTitle: String(localized: "settings.playback.audioEnhancements"),
                action: onToggleNightMode
            ),
            PlayerTrackOption(
                id: "dialogueBoost",
                accessibilityKey: "dialogueBoost",
                title: String(localized: "settings.playback.dialogueBoost"),
                subtitle: unavailableMessage ?? dialogueBoost.title,
                highlightsSubtitle: isAvailable && dialogueBoost != .off,
                systemImage: "person.wave.2",
                opensSubmenu: true,
                action: onShowDialogueBoost
            ),
        ]
    }
}
#endif
