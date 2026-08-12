#if os(tvOS)
import SwiftUI
import PlinxUI

private enum PlinxTVPlayerButtonChrome {
    static let compact = PlinxFocusSurfaceStyle(
        focusedScale: 1.03,
        focusedShadowRadius: 18,
        cornerRadius: 20,
        focusedFillOpacity: 0.12
    )
    static let primary = PlinxFocusSurfaceStyle(
        focusedScale: 1.035,
        focusedShadowRadius: 22,
        cornerRadius: 28,
        focusedFillOpacity: 0.16
    )
    static let marker = PlinxFocusSurfaceStyle(
        focusedScale: 1.025,
        focusedShadowRadius: 18,
        cornerRadius: 18,
        focusedFillOpacity: 0.12
    )
}

struct PlayerIconButton: View {
    let systemName: String
    var accessibilityLabel: String?
    let action: () -> Void

    private var accessibilityIdentifier: String {
        if systemName.hasPrefix("gobackward") { return "player.control.rewind" }
        if systemName.hasPrefix("goforward") { return "player.control.forward" }
        return "player.control.\(systemName)"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 82, height: 82)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(PlinxBrand.surface.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .plinxTVFocusButton(style: PlinxTVPlayerButtonChrome.compact)
        .accessibilityLabel(accessibilityLabel ?? systemName)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue("darkPlinxPlayerControl")
    }
}

struct PlayPauseButton: View {
    var isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 45, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 118, height: 118)
                .background {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(PlinxBrand.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.accentColor.opacity(0.22))
                        }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.46), lineWidth: 1.5)
                )
        }
        .plinxTVFocusButton(style: PlinxTVPlayerButtonChrome.primary)
        .accessibilityLabel(
            isPaused
                ? String(localized: "common.actions.play")
                : String(localized: "common.actions.pause")
        )
        .accessibilityIdentifier("player.control.playPause")
        .accessibilityValue("darkPlinxPrimaryPlayerControl")
    }
}

struct SkipMarkerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PlinxBrand.surface.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.38), lineWidth: 1)
            )
        }
        .plinxTVFocusButton(style: PlinxTVPlayerButtonChrome.marker)
        .accessibilityLabel(title)
        .accessibilityIdentifier("player.control.skipMarker")
        .accessibilityValue("darkPlinxSkipMarkerControl")
    }
}

struct PlayerSettingButton: View {
    var systemImage: String
    var action: () -> Void

    private var accessibilityIdentifier: String {
        systemImage.contains("caption")
            ? "player.control.subtitles"
            : "player.control.audio"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(PlinxBrand.surface.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
                )
        }
        .plinxTVFocusButton(
            style: PlinxFocusSurfaceStyle(
                focusedScale: 1.03,
                focusedShadowRadius: 16,
                cornerRadius: 17,
                focusedFillOpacity: 0.12
            )
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue("darkPlinxPlayerSettingControl")
    }
}
#endif
