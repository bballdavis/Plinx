import SwiftUI

public struct LiquidGlassModifier: ViewModifier {
    private let theme: PlinxTheme

    public init(theme: PlinxTheme = PlinxTheme()) {
        self.theme = theme
    }

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: theme.glass.cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.glass.cornerRadius, style: .continuous)
                            .stroke(.white.opacity(theme.glass.highlightOpacity), lineWidth: 1)
                    )
                    .shadow(color: .white.opacity(theme.glass.highlightOpacity), radius: 10, x: theme.glass.highlightOffset.width, y: theme.glass.highlightOffset.height)
                    .shadow(color: .black.opacity(theme.glass.shadowOpacity), radius: 12, x: theme.glass.shadowOffset.width, y: theme.glass.shadowOffset.height)
            )
    }
}

public extension View {
    func liquidGlassStyle(theme: PlinxTheme = PlinxTheme()) -> some View {
        modifier(LiquidGlassModifier(theme: theme))
    }
}
