import SwiftUI
import PlinxUI

enum PlinxBrandedLoadingPresentation: Sendable {
    case standard
    case heroIdentity
}

struct PlinxBrandedLoadingView: View {
    var titleKey: LocalizedStringKey?
    var logoAsset: PlinxBrandAsset
    var logoAccessibilityIdentifier: String
    var showsProgressView: Bool
    var presentation: PlinxBrandedLoadingPresentation
    /// When true the view fills the screen with the ambient brand shell.
    /// Use for full-screen splash and hero-loading contexts.
    var fillsBackground: Bool

    init(
        titleKey: LocalizedStringKey? = nil,
        logoAsset: PlinxBrandAsset = .lockupOnDark,
        logoAccessibilityIdentifier: String = "branding.logo",
        showsProgressView: Bool = true,
        presentation: PlinxBrandedLoadingPresentation = .standard,
        fillsBackground: Bool = false
    ) {
        self.titleKey = titleKey
        self.logoAsset = logoAsset
        self.logoAccessibilityIdentifier = logoAccessibilityIdentifier
        self.showsProgressView = showsProgressView
        self.presentation = presentation
        self.fillsBackground = fillsBackground
    }

    var body: some View {
        content
        .padding(24)
        .frame(maxWidth: fillsBackground ? .infinity : nil,
               maxHeight: fillsBackground ? .infinity : nil)
        .background {
            if fillsBackground {
                PlinxAmbientBackground(intensity: .hero)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .standard:
            standardContent
        case .heroIdentity:
            heroIdentityContent
        }
    }

    private var standardContent: some View {
        VStack(spacing: 18) {
            PlinxBrandLogoView(
                asset: logoAsset,
                accessibilityIdentifier: logoAccessibilityIdentifier,
                maxWidth: 240
            )

            if showsProgressView {
                PlinxLoadingIndicator(
                    size: .regular,
                    surface: .glass,
                    accessibilityIdentifier: "plinx.loading.branded"
                )
            }

            if let titleKey {
                Text(titleKey)
                    .font(.subheadline)
                    .foregroundStyle(fillsBackground ? Color.white.opacity(0.82) : .secondary)
            }
        }
    }

    private var heroIdentityContent: some View {
        VStack(spacing: 24) {
            PlinxLoadingIndicator(
                size: .hero,
                surface: .glass,
                accessibilityLabel: "Loading",
                accessibilityIdentifier: logoAccessibilityIdentifier
            )

            PlinxBrandLogoView(
                asset: .wordmarkWhite,
                accessibilityIdentifier: "plinx.loading.wordmark",
                maxWidth: heroWordmarkWidth
            )
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
        .accessibilityValue(PlinxBrandingSemantics.heroLoadingStyleValue)
        .accessibilityIdentifier("plinx.loading.branded")
    }

    private var heroWordmarkWidth: CGFloat {
        #if os(tvOS)
        260
        #else
        180
        #endif
    }

}
