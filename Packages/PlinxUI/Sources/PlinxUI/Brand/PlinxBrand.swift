import SwiftUI

/// Canonical Plinx identity tokens shared by the app and reusable UI package.
public enum PlinxBrand {
    public static let lime = Color(
        red: 158.0 / 255.0,
        green: 238.0 / 255.0,
        blue: 115.0 / 255.0
    )
    public static let teal = Color(
        red: 57.0 / 255.0,
        green: 158.0 / 255.0,
        blue: 145.0 / 255.0
    )
    public static let shell = Color(
        red: 11.0 / 255.0,
        green: 18.0 / 255.0,
        blue: 14.0 / 255.0
    )
    public static let surface = Color(
        red: 24.0 / 255.0,
        green: 33.0 / 255.0,
        blue: 29.0 / 255.0
    )
    public static let charcoal = Color(
        red: 16.0 / 255.0,
        green: 32.0 / 255.0,
        blue: 26.0 / 255.0
    )
    public static let white = Color.white

    public static var gradient: LinearGradient {
        LinearGradient(
            colors: [lime, teal],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public enum Ambient {
        public static let limeCenter = UnitPoint(x: 0.08, y: 0.02)
        public static let tealCenter = UnitPoint(x: 0.94, y: 0.96)
        public static let limeStartRadius: CGFloat = 12
        public static let limeEndRadius: CGFloat = 760
        public static let tealStartRadius: CGFloat = 24
        public static let tealEndRadius: CGFloat = 920
        public static let restrainedLimeOpacity = 0.04
        public static let restrainedTealOpacity = 0.06
        public static let heroLimeOpacity = 0.06
        public static let heroTealOpacity = 0.08
    }
}

/// Reusable dark-shell background with restrained, static brand light.
///
/// Ambient color is decorative only and intentionally stays below the contrast
/// budget for text, controls, and artwork.
public struct PlinxAmbientBackground: View {
    public enum Intensity: Sendable {
        case restrained
        case hero

        fileprivate var limeOpacity: Double {
            switch self {
            case .restrained: PlinxBrand.Ambient.restrainedLimeOpacity
            case .hero: PlinxBrand.Ambient.heroLimeOpacity
            }
        }

        fileprivate var tealOpacity: Double {
            switch self {
            case .restrained: PlinxBrand.Ambient.restrainedTealOpacity
            case .hero: PlinxBrand.Ambient.heroTealOpacity
            }
        }
    }

    private let intensity: Intensity

    public init(intensity: Intensity = .restrained) {
        self.intensity = intensity
    }

    public var body: some View {
        ZStack {
            PlinxBrand.shell

            RadialGradient(
                colors: [PlinxBrand.lime.opacity(intensity.limeOpacity), .clear],
                center: PlinxBrand.Ambient.limeCenter,
                startRadius: PlinxBrand.Ambient.limeStartRadius,
                endRadius: PlinxBrand.Ambient.limeEndRadius
            )

            RadialGradient(
                colors: [PlinxBrand.teal.opacity(intensity.tealOpacity), .clear],
                center: PlinxBrand.Ambient.tealCenter,
                startRadius: PlinxBrand.Ambient.tealStartRadius,
                endRadius: PlinxBrand.Ambient.tealEndRadius
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
