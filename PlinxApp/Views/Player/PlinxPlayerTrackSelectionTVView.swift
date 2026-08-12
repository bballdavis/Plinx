#if os(tvOS)
import SwiftUI
import PlinxUI

struct PlayerTrackSelectionView: View {
    var titleKey: LocalizedStringKey
    var tracks: [PlaybackSettingsTrack]
    var selectedTrackID: Int?
    var showOffOption: Bool
    var onSelect: (Int?) -> Void
    var onClose: () -> Void

    @FocusState private var focusedTrackKey: String?

    var body: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .restrained)

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("player.trackSelection")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text(titleKey)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)

                    if showOffOption {
                        trackButton(
                            key: "off",
                            title: String(localized: "player.settings.subtitles.off"),
                            subtitle: String(localized: "player.settings.subtitles.offDescription"),
                            isSelected: selectedTrackID == nil,
                            selection: nil
                        )
                    }

                    if tracks.isEmpty, !showOffOption {
                        Text("player.settings.audio.empty")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.68))
                            .padding(.vertical, 24)
                    } else {
                        ForEach(tracks) { track in
                            trackButton(
                                key: "track-\(track.id)",
                                title: track.title,
                                subtitle: track.subtitle,
                                isSelected: selectedTrackID == track.id,
                                selection: track.id
                            )
                        }
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 52)
            }
        }
        .onAppear {
            if showOffOption, selectedTrackID == nil {
                focusedTrackKey = "off"
            } else if let selectedTrackID,
                      tracks.contains(where: { $0.id == selectedTrackID }) {
                focusedTrackKey = "track-\(selectedTrackID)"
            } else if let first = tracks.first {
                focusedTrackKey = "track-\(first.id)"
            }
        }
        .onExitCommand(perform: onClose)
    }

    private func trackButton(
        key: String,
        title: String,
        subtitle: String?,
        isSelected: Bool,
        selection: Int?
    ) -> some View {
        Button {
            onSelect(selection)
        } label: {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.14)
                            : PlinxBrand.surface.opacity(0.92)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .focused($focusedTrackKey, equals: key)
        .plinxTVFocusButton(
            isSelected: isSelected,
            style: PlinxFocusSurfaceStyle(
                selectionOpacity: 0.62,
                focusedScale: 1,
                focusedShadowRadius: 16,
                cornerRadius: 20,
                focusedFillOpacity: 0.1
            )
        )
        .accessibilityIdentifier("player.track.\(key)")
        .accessibilityValue(isSelected ? "selectedPlinxTrack" : "PlinxTrack")
    }
}
#endif
