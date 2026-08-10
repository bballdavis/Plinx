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
    var titleKey: LocalizedStringResource?

    init(
        context: PlinxBrandedLoadingContext = .content,
        titleKey: LocalizedStringResource? = nil
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
        PlinxLoadingStateView(
            role: .content,
            label: titleKey,
            accessibilityLabel: titleKey,
            accessibilityIdentifier: "plinx.loading.content"
        )
    }

    private var heroIdentityContent: some View {
        VStack(spacing: 24) {
            PlinxLoadingIndicator(
                size: .hero,
                surface: .glass,
                accessibilityLabel: LocalizedStringResource(
                    "common.status.loading",
                    table: "Plinx"
                ),
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
        .accessibilityLabel(
            Text(LocalizedStringResource("common.status.loading", table: "Plinx"))
        )
        .accessibilityValue(PlinxBrandingSemantics.heroLoadingStyleValue)
        .accessibilityIdentifier("plinx.loading.branded")
    }

    private var heroWordmarkWidth: CGFloat {
        #if os(tvOS)
        240
        #else
        150
        #endif
    }
}
