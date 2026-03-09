import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// PlinxTheme — Liquid Glass Visual Language
// ─────────────────────────────────────────────────────────────────────────────
//
// The Plinx visual identity is built on Apple's Liquid Glass design language
// (iOS 26+), adapted for a children's media app:
//
//   • Physicality: Refractive depth, specular highlights, squishy animations
//   • Palette: Bright primary colors against deep dark backgrounds
//   • Geometry: High-radius rounded corners, continuous curves
//   • Feel: Every surface looks like it could be poked, squeezed, or bounced
//
// PlinxTheme is a value type (struct, Sendable) injected via SwiftUI's
// environment. All Plinx views read `@Environment(\.plinxTheme)`.
//
// ─────────────────────────────────────────────────────────────────────────────

/// The complete visual theme for Plinx's Liquid Glass design language.
public struct PlinxTheme: Sendable {

    // MARK: - Color Palette

    /// Color palette — bright, high-contrast, kid-friendly.
    public struct Palette: Sendable {
        /// Primary brand color (headings, key UI elements).
        public let primary: Color
        /// Secondary brand color (accents, badges).
        public let secondary: Color
        /// Accent/interactive color (buttons, links, progress bars).
        public let accent: Color
        /// Deep background color (near-black for contrast).
        public let background: Color
        /// Surface color (cards, sheets, elevated surfaces).
        public let surface: Color
        /// Text on top of primary color.
        public let onPrimary: Color
        /// Success state color.
        public let success: Color
        /// Warning/caution state color.
        public let warning: Color
    }

    // MARK: - Glass Properties

    /// Glass material properties — specular highlights, refractive shadows.
    public struct Glass: Sendable {
        /// Corner radius for glass surfaces (continuous curve).
        public let cornerRadius: CGFloat
        /// Opacity of the specular highlight (top-left glow).
        public let highlightOpacity: CGFloat
        /// Opacity of the depth shadow (bottom-right).
        public let shadowOpacity: CGFloat
        /// Offset of the specular highlight.
        public let highlightOffset: CGSize
        /// Offset of the depth shadow.
        public let shadowOffset: CGSize
        /// Blur radius for the specular highlight.
        public let highlightBlur: CGFloat
        /// Blur radius for the depth shadow.
        public let shadowBlur: CGFloat
        /// Material blur style for glass surfaces.
        public let material: Material

        public init(
            cornerRadius: CGFloat = 22,
            highlightOpacity: CGFloat = 0.45,
            shadowOpacity: CGFloat = 0.25,
            highlightOffset: CGSize = CGSize(width: -4, height: -6),
            shadowOffset: CGSize = CGSize(width: 6, height: 8),
            highlightBlur: CGFloat = 10,
            shadowBlur: CGFloat = 12,
            material: Material = .thinMaterial
        ) {
            self.cornerRadius = cornerRadius
            self.highlightOpacity = highlightOpacity
            self.shadowOpacity = shadowOpacity
            self.highlightOffset = highlightOffset
            self.shadowOffset = shadowOffset
            self.highlightBlur = highlightBlur
            self.shadowBlur = shadowBlur
            self.material = material
        }
    }

    // MARK: - Animation Curves

    /// Spring animation parameters — squishy, tactile feel.
    public struct Springs: Sendable {
        /// Default interaction spring (button press, tab switch).
        public let interactive: Animation
        /// Bouncy spring for emphasis (entrance, celebration).
        public let bouncy: Animation
        /// Gentle spring for subtle transitions.
        public let gentle: Animation
        /// Snappy spring for navigation transitions.
        public let snappy: Animation
    }

    // MARK: - Typography Scale

    /// Typography style — neutral, geometric, highly legible (Inter-inspired).
    public struct Typography: Sendable {
        /// A specific typographic style combining font, tracking, and line spacing.
        public struct Style: Sendable {
            public let font: Font
            public let tracking: CGFloat
            public let lineSpacing: CGFloat

            public init(size: CGFloat, weight: Font.Weight, tracking: CGFloat, lineHeight: CGFloat) {
                // We use system font (SF Pro) as the native "soft geometric" engine.
                self.font = .system(size: size, weight: weight)
                self.tracking = size * tracking
                // lineSpacing is the additional space between lines (approximate).
                self.lineSpacing = size * (lineHeight - 1.0)
            }
        }

        /// Large display font (hero sections).
        public let display: Style
        /// Screen title font.
        public let title: Style
        /// Section heading font.
        public let heading: Style
        /// Body text font.
        public let body: Style
        /// Caption/small text font.
        public let caption: Style
        /// Button text font.
        public let button: Style
    }

    // MARK: - Properties

    public let palette: Palette
    public let glass: Glass
    public let springs: Springs
    public let typography: Typography

    public init(
        palette: Palette = .default,
        glass: Glass = .default,
        springs: Springs = .default,
        typography: Typography = .default
    ) {
        self.palette = palette
        self.glass = glass
        self.springs = springs
        self.typography = typography
    }
}

// MARK: - Default Palette

public extension PlinxTheme.Palette {
    static let `default` = PlinxTheme.Palette(
        primary: .blue,
        secondary: .orange,
        accent: .pink,
        background: Color(red: 0.045, green: 0.07, blue: 0.055),
        surface: Color(white: 0.12),
        onPrimary: .white,
        success: .green,
        warning: .yellow
    )
}

// MARK: - Default Glass

public extension PlinxTheme.Glass {
    static let `default` = PlinxTheme.Glass()

    /// Smaller glass for inline elements (badges, pills).
    static let compact = PlinxTheme.Glass(
        cornerRadius: 12,
        highlightOpacity: 0.35,
        shadowOpacity: 0.2,
        highlightOffset: CGSize(width: -2, height: -3),
        shadowOffset: CGSize(width: 3, height: 4),
        highlightBlur: 6,
        shadowBlur: 8
    )

    /// Large glass for hero cards and modals.
    static let hero = PlinxTheme.Glass(
        cornerRadius: 28,
        highlightOpacity: 0.5,
        shadowOpacity: 0.3,
        highlightOffset: CGSize(width: -6, height: -8),
        shadowOffset: CGSize(width: 8, height: 12),
        highlightBlur: 16,
        shadowBlur: 20
    )
}

// MARK: - Default Springs

public extension PlinxTheme.Springs {
    static let `default` = PlinxTheme.Springs(
        interactive: .spring(response: 0.3, dampingFraction: 0.7),
        bouncy: .spring(response: 0.5, dampingFraction: 0.5),
        gentle: .spring(response: 0.6, dampingFraction: 0.85),
        snappy: .spring(response: 0.25, dampingFraction: 0.8)
    )
}

// MARK: - Default Typography

public extension PlinxTheme.Typography {
    static let `default` = PlinxTheme.Typography(
        display: Style(size: 36, weight: .semibold, tracking: 0.0, lineHeight: 1.3),
        title: Style(size: 24, weight: .medium, tracking: 0.01, lineHeight: 1.3),
        heading: Style(size: 18, weight: .medium, tracking: 0.01, lineHeight: 1.3),
        body: Style(size: 15, weight: .regular, tracking: 0.015, lineHeight: 1.45),
        caption: Style(size: 12, weight: .regular, tracking: 0.03, lineHeight: 1.4),
        button: Style(size: 16, weight: .medium, tracking: 0.02, lineHeight: 1.2)
    )
}

// MARK: - View Modifiers

public extension View {
    /// Applies a Plinx typographic style to a View.
    @ViewBuilder
    func plinxStyle(_ style: PlinxTheme.Typography.Style) -> some View {
        self.font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}
