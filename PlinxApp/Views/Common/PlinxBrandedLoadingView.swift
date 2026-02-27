import SwiftUI
import PlinxUI

struct PlinxBrandedLoadingView: View {
    @Environment(\.plinxTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var titleKey: LocalizedStringKey?

    init(titleKey: LocalizedStringKey? = nil) {
        self.titleKey = titleKey
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(colorScheme == .dark ? "LogoFullWhite" : "LogoFullColor")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)

            ProgressView()
                .controlSize(.regular)
                .tint(theme.palette.primary)

            if let titleKey {
                Text(titleKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}
