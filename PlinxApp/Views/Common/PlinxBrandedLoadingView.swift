import SwiftUI
import PlinxUI

enum PlinxBrandedLoadingContext: Sendable {
    /// A full-screen transition between launch, session hydration, and the
    /// first home load. Every call site intentionally shares one composition.
    case appTransition
    /// A contextual wait inside an already-established screen or navigation
    /// hierarchy. These states stay branded without repeating the full logo.
    case content
}

struct PlinxBrandedLoadingView: View {
    var context: PlinxBrandedLoadingContext
    var titleKey: LocalizedStringKey?

    init(
        context: PlinxBrandedLoadingContext = .content,
        titleKey: LocalizedStringKey? = nil
    ) {
        self.context = context
        self.titleKey = titleKey
    }

    var body: some View {
        switch context {
        case .appTransition:
            heroIdentityContent
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    PlinxAmbientBackground(intensity: .hero)
                }
        case .content:
            contentLoading
                .padding(24)
        }
    }

    private var contentLoading: some View {
        VStack(spacing: 18) {
            PlinxLoadingIndicator(
                size: .regular,
                surface: .glass,
                accessibilityIdentifier: "plinx.loading.content"
            )

            if let titleKey {
                Text(titleKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var heroIdentityContent: some View {
        VStack(spacing: 24) {
            PlinxLoadingIndicator(
                size: .hero,
                surface: .glass,
                accessibilityLabel: "Loading",
                accessibilityIdentifier: "plinx.loading.heroBeacon"
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
