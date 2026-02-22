// ─────────────────────────────────────────────────────────────────────────────
// PlinxMediaBackdropGradient.swift — iOS 26 SDK compatible replacement
// ─────────────────────────────────────────────────────────────────────────────
//
// Strimr's MediaBackdropGradient uses `Color.background` which is ambiguous
// in the iOS 26 SDK (resolves to `BackgroundStyle` instead of `Color`).
//
// Fix: use `Color(uiColor: .systemBackground)` for explicit Color typing.
//
// Upstream PR: disambiguate Color.background in MediaBackdropGradient
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct MediaBackdropGradient: View {
    let colors: [Color]

    var body: some View {
        let bg = Color(uiColor: .systemBackground)
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
    static func colors(for media: MediaDisplayItem) -> [Color] {
        guard let blur = media.ultraBlurColors else { return [] }
        return [
            Color(hex: blur.topLeft),
            Color(hex: blur.topRight),
            Color(hex: blur.bottomRight),
            Color(hex: blur.bottomLeft),
        ]
    }
}
