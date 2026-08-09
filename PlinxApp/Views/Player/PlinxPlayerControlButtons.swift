import SwiftUI

enum PlinxPlayerControlLayout {
    static func scale(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        switch (horizontalSizeClass, verticalSizeClass) {
        case (.regular, .regular):
            2
        case (.regular, .compact):
            1.65
        case (.compact, .compact):
            1.45
        default:
            1.3
        }
    }

    static func exitButtonSize(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        switch (horizontalSizeClass, verticalSizeClass) {
        case (.regular, .regular):
            104
        case (.regular, .compact):
            96
        case (.compact, .compact):
            88
        default:
            80
        }
    }

    static func exitIconSize(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        exitButtonSize(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        ) * 0.34
    }
}

private struct PlinxPlayerControlMetrics {
    let scale: CGFloat

    var seekButtonSize: CGFloat { 58 * scale }
    var seekIconSize: CGFloat { 20 * scale }
    var seekCornerRadius: CGFloat { 22 * scale }
    var playButtonSize: CGFloat { 72 * scale }
    var playIconSize: CGFloat { 28 * scale }
    var playCornerRadius: CGFloat { 26 * scale }
    var borderWidth: CGFloat { max(2, scale) }
}

struct PlayerIconButton: View {
    let systemName: String
    var accessibilityLabel: String?
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var metrics: PlinxPlayerControlMetrics {
        PlinxPlayerControlMetrics(
            scale: PlinxPlayerControlLayout.scale(
                horizontalSizeClass: horizontalSizeClass,
                verticalSizeClass: verticalSizeClass
            )
        )
    }

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(
                cornerRadius: metrics.seekCornerRadius,
                style: .continuous
            )
            Image(systemName: systemName)
                .font(.system(size: metrics.seekIconSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: metrics.seekButtonSize, height: metrics.seekButtonSize)
                .background(
                    chrome.fill(Color.black.opacity(reduceTransparency ? 1 : 0.84))
                )
                .overlay(
                    chrome.stroke(
                        Color.white.opacity(0.78),
                        lineWidth: metrics.borderWidth
                    )
                )
                .shadow(
                    color: Color.black.opacity(0.58),
                    radius: 12 * metrics.scale,
                    x: 0,
                    y: 6 * metrics.scale
                )
        }
        .accessibilityLabel(accessibilityLabel ?? systemName)
        .buttonStyle(.plain)
    }
}

struct PlayPauseButton: View {
    var isPaused: Bool
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var metrics: PlinxPlayerControlMetrics {
        PlinxPlayerControlMetrics(
            scale: PlinxPlayerControlLayout.scale(
                horizontalSizeClass: horizontalSizeClass,
                verticalSizeClass: verticalSizeClass
            )
        )
    }

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(
                cornerRadius: metrics.playCornerRadius,
                style: .continuous
            )
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: metrics.playIconSize, weight: .black))
                .foregroundStyle(.white)
                .frame(width: metrics.playButtonSize, height: metrics.playButtonSize)
                .background {
                    ZStack {
                        chrome.fill(
                            Color.black.opacity(reduceTransparency ? 1 : 0.9)
                        )
                        chrome.fill(
                            Color.brandPrimary.opacity(reduceTransparency ? 0.72 : 0.62)
                        )
                    }
                }
                .overlay(
                    chrome.stroke(
                        Color.white.opacity(0.88),
                        lineWidth: metrics.borderWidth
                    )
                )
                .shadow(
                    color: Color.black.opacity(0.62),
                    radius: 14 * metrics.scale,
                    x: 0,
                    y: 7 * metrics.scale
                )
        }
        .accessibilityLabel(
            isPaused
                ? String(localized: "common.actions.play")
                : String(localized: "common.actions.pause")
        )
        .buttonStyle(.plain)
    }
}

struct SkipMarkerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 18, style: .continuous)
            HStack(spacing: 10) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(chrome.fill(.thinMaterial))
            .overlay(
                chrome.stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1)
            )
            .shadow(
                color: Color.brandPrimary.opacity(0.12),
                radius: 8,
                x: 0,
                y: 6
            )
        }
        .accessibilityLabel(title)
        .buttonStyle(.plain)
    }
}

struct PlayerSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 14, style: .continuous)
            Image(systemName: "gearshape")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(chrome.fill(Color.brandPrimary.opacity(0.14)))
                .overlay(
                    chrome.stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1)
                )
                .shadow(
                    color: Color.brandPrimary.opacity(0.1),
                    radius: 8,
                    x: 0,
                    y: 5
                )
        }
        .accessibilityLabel(String(localized: "settings.title"))
        .buttonStyle(.plain)
    }
}

struct RotationLockButton: View {
    var isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 14, style: .continuous)
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    chrome.fill(Color.brandPrimary.opacity(isLocked ? 0.24 : 0.14))
                )
                .overlay(
                    chrome.stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1)
                )
                .shadow(
                    color: Color.brandPrimary.opacity(0.1),
                    radius: 8,
                    x: 0,
                    y: 5
                )
        }
        .accessibilityLabel(
            String(
                localized: isLocked
                    ? "player.controls.rotation.unlock"
                    : "player.controls.rotation.lock"
            )
        )
        .buttonStyle(.plain)
    }
}
