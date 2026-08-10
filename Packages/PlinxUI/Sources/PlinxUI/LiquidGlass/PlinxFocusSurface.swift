import SwiftUI

/// Visual constants for Plinx's restrained selected and focused surfaces.
public struct PlinxFocusSurfaceStyle: Sendable, Equatable {
    public let selectionOpacity: Double
    public let focusRingOpacity: Double
    public let focusedScale: CGFloat
    public let focusedShadowRadius: CGFloat

    public init(
        selectionOpacity: Double = 0.72,
        focusRingOpacity: Double = 0.98,
        focusedScale: CGFloat = 1.035,
        focusedShadowRadius: CGFloat = 18
    ) {
        self.selectionOpacity = selectionOpacity
        self.focusRingOpacity = focusRingOpacity
        self.focusedScale = focusedScale
        self.focusedShadowRadius = focusedShadowRadius
    }

    /// The calm premium default: persistent selection, with a brighter live-focus cue.
    public static let calmPremium = Self()
}

/// Separates persistent selection from transient platform focus.
public struct PlinxFocusSurfaceModifier: ViewModifier {
    public let isSelected: Bool
    public let isFocused: Bool
    public let style: PlinxFocusSurfaceStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isSelected: Bool,
        isFocused: Bool,
        style: PlinxFocusSurfaceStyle = .calmPremium
    ) {
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.style = style
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let focusScale = isFocused && !reduceMotion ? style.focusedScale : 1

        content
            .overlay {
                shape.stroke(
                    PlinxBrand.gradient,
                    lineWidth: isFocused ? 3 : (isSelected ? 2 : 0)
                )
                .opacity(isFocused ? style.focusRingOpacity : style.selectionOpacity)
            }
            .shadow(
                color: isFocused ? PlinxBrand.lime.opacity(0.30) : .clear,
                radius: isFocused ? style.focusedShadowRadius : 0
            )
            .scaleEffect(focusScale)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: isFocused
            )
    }
}

public extension View {
    /// Applies Plinx's calm focus treatment without conflating selection and focus.
    func plinxFocusSurface(
        isSelected: Bool,
        isFocused: Bool,
        style: PlinxFocusSurfaceStyle = .calmPremium
    ) -> some View {
        modifier(PlinxFocusSurfaceModifier(
            isSelected: isSelected,
            isFocused: isFocused,
            style: style
        ))
    }
}
