// ─────────────────────────────────────────────────────────────────────────────
// MediaBackdropGradient — artwork-tinted backdrop behind detail and hero views
// ─────────────────────────────────────────────────────────────────────────────
//
// Four radial gradients from the artwork's corner colors over the screen
// background. Without corner colors (or without exactly four) the background
// fades in steps instead. The background is an explicit `Color` on each
// platform: `Color.background` is ambiguous in the iOS 26 SDK, and the
// "Background" asset is not part of Plinx.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct MediaBackdropGradient: View {
    let colors: [Color]

    var body: some View {
        #if os(tvOS)
        let bg = Color.black
        #else
        let bg = Color(uiColor: .systemBackground)
        #endif
        let gradientColors = colors.count == 4 ? colors : [
            bg.opacity(0.85),
            bg.opacity(0.7),
            bg.opacity(0.55),
            bg.opacity(0.4),
        ]

        GeometryReader { geo in
            ZStack {
                bg.ignoresSafeArea()

                // Top Left
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[0], .clear]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )

                // Top Right
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[1], .clear]),
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )

                // Bottom Right
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[2], .clear]),
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )

                // Bottom Left
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[3], .clear]),
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )
            }
        }
    }
}

extension MediaBackdropGradient {
    /// The artwork's corner colors in gradient order, or none when the provider sent none.
    static func colors(for media: MediaDisplayItem) -> [Color] {
        guard let corners = media.artworkCornerColors else { return [] }
        return [
            Color(hex: corners.topLeft),
            Color(hex: corners.topRight),
            Color(hex: corners.bottomRight),
            Color(hex: corners.bottomLeft),
        ]
    }
}
