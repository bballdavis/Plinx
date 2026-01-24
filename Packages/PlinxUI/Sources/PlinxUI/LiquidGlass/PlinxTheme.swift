import SwiftUI

public struct PlinxTheme: Sendable {
    public struct Palette: Sendable {
        public let primary: Color
        public let secondary: Color
        public let accent: Color
        public let background: Color
        public let surface: Color
    }

    public struct Glass: Sendable {
        public let cornerRadius: CGFloat
        public let highlightOpacity: CGFloat
        public let shadowOpacity: CGFloat
        public let highlightOffset: CGSize
        public let shadowOffset: CGSize
    }

    public let palette: Palette
    public let glass: Glass

    public init(
        palette: Palette = .default,
        glass: Glass = .default
    ) {
        self.palette = palette
        self.glass = glass
    }
}

public extension PlinxTheme.Palette {
    static let `default` = PlinxTheme.Palette(
        primary: .blue,
        secondary: .orange,
        accent: .pink,
        background: Color(.systemBackground),
        surface: Color(.secondarySystemBackground)
    )
}

public extension PlinxTheme.Glass {
    static let `default` = PlinxTheme.Glass(
        cornerRadius: 22,
        highlightOpacity: 0.45,
        shadowOpacity: 0.25,
        highlightOffset: CGSize(width: -4, height: -6),
        shadowOffset: CGSize(width: 6, height: 8)
    )
}
