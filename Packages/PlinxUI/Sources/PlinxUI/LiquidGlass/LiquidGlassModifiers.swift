import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Liquid Glass Modifiers
// ─────────────────────────────────────────────────────────────────────────────
//
// ViewModifiers that apply the Liquid Glass visual treatment:
//   • Thin material background (frosted glass)
//   • Specular highlight (top-left white glow = "light source")
//   • Depth shadow (bottom-right dark shadow)
//   • White stroke border (edge refraction)
//   • Continuous-curve rounded rectangle
//
// ─────────────────────────────────────────────────────────────────────────────

/// Applies the standard Liquid Glass surface treatment.
public struct LiquidGlassModifier: ViewModifier {
    private let theme: PlinxTheme
    private let glassStyle: PlinxTheme.Glass

    public init(theme: PlinxTheme = PlinxTheme(), style: PlinxTheme.Glass? = nil) {
        self.theme = theme
        self.glassStyle = style ?? theme.glass
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: glassStyle.cornerRadius, style: .continuous)

        content
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                shape
                    .fill(.thinMaterial)
                    .overlay(
                        shape
                            .stroke(.white.opacity(glassStyle.highlightOpacity), lineWidth: 1)
                    )
                    // Specular highlight (light source top-left)
                    .shadow(
                        color: .white.opacity(glassStyle.highlightOpacity),
                        radius: glassStyle.highlightBlur,
                        x: glassStyle.highlightOffset.width,
                        y: glassStyle.highlightOffset.height
                    )
                    // Depth shadow (bottom-right)
                    .shadow(
                        color: .black.opacity(glassStyle.shadowOpacity),
                        radius: glassStyle.shadowBlur,
                        x: glassStyle.shadowOffset.width,
                        y: glassStyle.shadowOffset.height
                    )
            )
    }
}

/// Applies glass treatment without padding — for wrapping existing padded content.
public struct LiquidGlassBackgroundModifier: ViewModifier {
    private let glassStyle: PlinxTheme.Glass

    public init(style: PlinxTheme.Glass = .default) {
        self.glassStyle = style
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: glassStyle.cornerRadius, style: .continuous)

        content
            .background(
                shape.fill(.thinMaterial)
                    .overlay(shape.stroke(.white.opacity(glassStyle.highlightOpacity), lineWidth: 1))
                    .shadow(
                        color: .white.opacity(glassStyle.highlightOpacity),
                        radius: glassStyle.highlightBlur,
                        x: glassStyle.highlightOffset.width,
                        y: glassStyle.highlightOffset.height
                    )
                    .shadow(
                        color: .black.opacity(glassStyle.shadowOpacity),
                        radius: glassStyle.shadowBlur,
                        x: glassStyle.shadowOffset.width,
                        y: glassStyle.shadowOffset.height
                    )
            )
            .clipShape(shape)
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies the standard Liquid Glass surface with padding.
    func liquidGlassStyle(theme: PlinxTheme = PlinxTheme()) -> some View {
        modifier(LiquidGlassModifier(theme: theme))
    }

    /// Applies Liquid Glass with a specific glass variant (compact, hero, etc.).
    func liquidGlassStyle(variant: PlinxTheme.Glass) -> some View {
        modifier(LiquidGlassModifier(style: variant))
    }

    /// Applies Liquid Glass background only (no padding). Use when you manage
    /// your own padding/layout.
    func liquidGlassBackground(style: PlinxTheme.Glass = .default) -> some View {
        modifier(LiquidGlassBackgroundModifier(style: style))
    }
}
