#if os(tvOS)
import SwiftUI
import PlinxUI

/// One app-owned focus treatment for tvOS buttons. The platform focus plate is
/// disabled so labels keep their dark Plinx surface and readable foreground.
private struct PlinxTVFocusButtonModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    let isSelected: Bool
    let style: PlinxFocusSurfaceStyle

    func body(content: Content) -> some View {
        content
            .buttonStyle(PlinkButtonStyle())
            .focusEffectDisabled()
            .plinxFocusSurface(
                isSelected: isSelected,
                isFocused: isFocused,
                style: style
            )
    }
}

extension View {
    func plinxTVFocusButton(
        isSelected: Bool = false,
        style: PlinxFocusSurfaceStyle = .calmPremium
    ) -> some View {
        modifier(
            PlinxTVFocusButtonModifier(
                isSelected: isSelected,
                style: style
            )
        )
    }
}
#endif
