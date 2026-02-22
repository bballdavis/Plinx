import SwiftUI
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// LiquidGlassButton — The Plinx "Plink" Button
// ─────────────────────────────────────────────────────────────────────────────
//
// Every interactive element in Plinx triggers the signature "Plink" feedback:
//   1. Heavy haptic impact (UIImpactFeedbackGenerator)
//   2. Audio "plink" sound (PlinkAudioManager → bundled .caf file)
//   3. Spring scale animation (press → shrink 0.92, release → bounce back)
//
// The button uses Liquid Glass styling: frosted material background,
// specular highlight, depth shadow, continuous-curve corners.
//
// ─────────────────────────────────────────────────────────────────────────────

/// A button styled with Liquid Glass that triggers haptic + audio feedback.
///
/// Usage:
/// ```swift
/// LiquidGlassButton("Play") { startPlayback() }
/// LiquidGlassButton("Settings", style: .compact) { openSettings() }
/// ```
public struct LiquidGlassButton: View {
    private let title: String
    private let icon: String?
    private let glassStyle: PlinxTheme.Glass
    private let action: () -> Void
    private let haptics: HapticManaging
    private let audio: PlinkAudioManaging
    private let theme: PlinxTheme

    @State private var isPressed = false

    public init(
        _ title: String,
        icon: String? = nil,
        style: PlinxTheme.Glass? = nil,
        theme: PlinxTheme = PlinxTheme(),
        haptics: HapticManaging = HapticManager(),
        audio: PlinkAudioManaging = PlinkAudioManager(),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.glassStyle = style ?? theme.glass
        self.theme = theme
        self.haptics = haptics
        self.audio = audio
        self.action = action
    }

    public var body: some View {
        Button(action: {
            // "Plink" — the signature Plinx interaction
            audio.playPlink()
            haptics.plink()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .font(theme.typography.heading)
            }
            .foregroundStyle(theme.palette.onPrimary)
            .liquidGlassStyle(variant: glassStyle)
        }
        .buttonStyle(PlinkButtonStyle(springs: theme.springs))
    }
}

// MARK: - PlinkButtonStyle

/// Custom button style that adds the spring-scale animation on press.
/// Separated from LiquidGlassButton so it can be reused on other elements.
public struct PlinkButtonStyle: ButtonStyle {
    private let springs: PlinxTheme.Springs

    public init(springs: PlinxTheme.Springs = .default) {
        self.springs = springs
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(springs.interactive, value: configuration.isPressed)
    }
}
