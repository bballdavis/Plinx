import SwiftUI
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// LiquidGlassButton — The Plinx "Plink" Button
// ─────────────────────────────────────────────────────────────────────────────
//
// Every LiquidGlassButton triggers tactile and visual feedback:
//   1. Heavy haptic impact (UIImpactFeedbackGenerator)
//   2. Spring scale animation (press → shrink 0.92, release → bounce back)
//
// The button uses Liquid Glass styling: frosted material background,
// specular highlight, depth shadow, continuous-curve corners.
//
// ─────────────────────────────────────────────────────────────────────────────

/// A button styled with Liquid Glass that triggers haptic feedback.
///
/// Usage:
/// ```swift
/// LiquidGlassButton("Play") { startPlayback() }
/// LiquidGlassButton("Settings", style: .compact) { openSettings() }
/// LiquidGlassButton(LocalizedStringResource("Unlock", table: "Plinx")) { ... }
/// ```
public struct LiquidGlassButton: View {
    private let title: LocalizedStringResource
    private let icon: String?
    private let glassStyle: PlinxTheme.Glass
    private let action: () -> Void
    private let haptics: HapticManaging
    private let theme: PlinxTheme

    @State private var isPressed = false

    public init(
        _ title: LocalizedStringResource,
        icon: String? = nil,
        style: PlinxTheme.Glass? = nil,
        theme: PlinxTheme = PlinxTheme(),
        haptics: HapticManaging = HapticManager(),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.glassStyle = style ?? theme.glass
        self.theme = theme
        self.haptics = haptics
        self.action = action
    }

    public var body: some View {
        Button(action: {
            haptics.plink()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                }
                Text(title)
                    .plinxStyle(theme.typography.button)
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
