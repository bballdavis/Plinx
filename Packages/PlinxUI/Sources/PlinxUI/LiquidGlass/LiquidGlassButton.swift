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
/// LiquidGlassButton(
///     LocalizedStringResource("Unlock", table: "Plinx"),
///     treatment: .brand
/// ) { ... }
/// ```
public enum LiquidGlassButtonTreatment: Sendable {
    case glass
    case brand
}

public struct LiquidGlassButton: View {
    private let title: LocalizedStringResource
    private let icon: String?
    private let glassStyle: PlinxTheme.Glass
    private let treatment: LiquidGlassButtonTreatment
    private let action: () -> Void
    private let haptics: HapticManaging
    private let theme: PlinxTheme

    @State private var isPressed = false

    public init(
        _ title: LocalizedStringResource,
        icon: String? = nil,
        style: PlinxTheme.Glass? = nil,
        treatment: LiquidGlassButtonTreatment = .glass,
        theme: PlinxTheme = PlinxTheme(),
        haptics: HapticManaging = HapticManager(),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.glassStyle = style ?? theme.glass
        self.treatment = treatment
        self.theme = theme
        self.haptics = haptics
        self.action = action
    }

    public var body: some View {
        Button(action: {
            haptics.plink()
            action()
        }) {
            styledLabel
        }
        .buttonStyle(PlinkButtonStyle(springs: theme.springs))
    }

    private var label: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
            }
            Text(title)
                .plinxStyle(theme.typography.button)
        }
    }

    @ViewBuilder
    private var styledLabel: some View {
        switch treatment {
        case .glass:
            label
                .foregroundStyle(theme.palette.onPrimary)
                .liquidGlassStyle(variant: glassStyle)
        case .brand:
            label
                .foregroundStyle(theme.palette.background)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(brandSurface)
        }
    }

    private var brandSurface: some View {
        let shape = RoundedRectangle(
            cornerRadius: glassStyle.cornerRadius,
            style: .continuous
        )

        return shape
            .fill(PlinxBrand.gradient)
            .overlay(shape.fill(Color.white.opacity(0.08)))
            .overlay(
                shape.stroke(
                    Color.white.opacity(glassStyle.highlightOpacity),
                    lineWidth: 1
                )
            )
            .shadow(
                color: Color.white.opacity(glassStyle.highlightOpacity),
                radius: glassStyle.highlightBlur,
                x: glassStyle.highlightOffset.width,
                y: glassStyle.highlightOffset.height
            )
            .shadow(
                color: Color.black.opacity(glassStyle.shadowOpacity),
                radius: glassStyle.shadowBlur,
                x: glassStyle.shadowOffset.width,
                y: glassStyle.shadowOffset.height
            )
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
