import SwiftUI
import PlinxCore
import PlinxUI

#if !os(tvOS)
struct PlinxScrollingHeaderRow: View {
    let title: String
    let showsSettingsButton: Bool
    let showsSearchButton: Bool
    let showsLogo: Bool
    let chromeButtonSize: PlinxChromeButtonSizePreference
    let onSearch: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            leadingContent
            Spacer()

            if showsSearchButton {
                PlinxChromeButton(systemImage: "magnifyingglass", action: onSearch)
                    .accessibilityIdentifier("home.header.search")
            }

            if showsSettingsButton {
                PlinxChromeButton(systemImage: "gearshape.fill", action: onSettings)
                    .accessibilityIdentifier("home.header.settings")
            } else if !showsSearchButton {
                Color.clear
                    .frame(width: chromeButtonSize.sideLength, height: chromeButtonSize.sideLength)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var leadingContent: some View {
        if showsLogo {
            let logoHeight = PlinxBrandLayoutMetrics.homeHeaderLogoHeight(
                chromeButtonSideLength: chromeButtonSize.sideLength
            )
            PlinxHomeHeaderLogoView(
                accessibilityIdentifier: "home.header.logo",
                maxWidth: PlinxBrandLayoutMetrics.homeHeaderLogoWidth(
                    chromeButtonSideLength: chromeButtonSize.sideLength
                ),
                logoHeight: logoHeight
            )
        } else {
            Text(title.plinxLocalized)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
    }
}
#endif

extension String {
    var plinxLocalized: String {
        NSLocalizedString(self, tableName: "Plinx", bundle: .main, comment: "")
    }
}
