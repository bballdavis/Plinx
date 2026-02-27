import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx-branded sign-in view (replaces Strimr's SignInView)
//
// Strimr's original references Asset Catalog images we don't ship.
// This replacement uses the Plinx Liquid Glass theme and Plinx brand assets.
// ─────────────────────────────────────────────────────────────────────────────

struct SignInView: View {
    @State private var viewModel: SignInViewModel
    @Environment(\.plinxTheme) private var theme

    init(viewModel: SignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                PlinxBrandLogoView(
                    preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                    accessibilityIdentifier: "signIn.logo.fullColor"
                )

                Text("signIn.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack {
                    if viewModel.isAuthenticating {
                        ProgressView().tint(theme.palette.primary)
                    }
                    Text(viewModel.isAuthenticating
                         ? "signIn.button.waiting"
                         : "signIn.button.continue")
                        .plinxStyle(theme.typography.button)
                }
                .foregroundStyle(theme.palette.onPrimary)
                .frame(maxWidth: .infinity)
                .liquidGlassStyle(variant: theme.glass)
            }
            .buttonStyle(PlinkButtonStyle(springs: theme.springs))
            .disabled(viewModel.isAuthenticating)
            .opacity(viewModel.isAuthenticating ? 0.7 : 1)
            .accessibilityIdentifier("signIn.primaryButton")
            .accessibilityValue(PlinxBrandingSemantics.signInPrimaryButtonStyleValue)

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") {
                    viewModel.cancelSignIn()
                }
                .padding(.top, 4)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(theme.palette.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(24)
        .background(theme.palette.background.ignoresSafeArea())
    }
}
