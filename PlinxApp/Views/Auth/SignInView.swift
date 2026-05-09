import SwiftUI
import PlinxUI

#if os(tvOS)
import CoreImage.CIFilterBuiltins
import UIKit
#endif

#if os(tvOS)
typealias PlinxSignInViewModel = SignInTVViewModel
#else
typealias PlinxSignInViewModel = SignInViewModel
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Plinx-branded sign-in view (replaces Strimr's SignInView)
//
// Strimr's original references Asset Catalog images we don't ship.
// This replacement uses the Plinx Liquid Glass theme and Plinx brand assets.
// ─────────────────────────────────────────────────────────────────────────────

struct SignInView: View {
    @State private var viewModel: PlinxSignInViewModel
    @Environment(\.plinxTheme) private var theme

    #if os(tvOS)
    private let ciContext = CIContext()
    #endif

    init(viewModel: PlinxSignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        #if os(tvOS)
        tvOSBody
        #else
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                PlinxBrandLogoView(
                    preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                    accessibilityIdentifier: "signIn.logo.fullColor"
                )

                Text("signIn.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack {
                    if viewModel.isAuthenticating {
                        ProgressView().tint(Color.accentColor)
                    }
                    Text(viewModel.isAuthenticating
                         ? "signIn.button.waiting"
                         : "signIn.button.continue")
                        .plinxStyle(theme.typography.button)
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
                )
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
        .background(Color.white.ignoresSafeArea())
        #endif
    }
}

#if os(tvOS)
extension SignInView {
    private var tvOSBody: some View {
        ZStack {
            LinearGradient.plinxBrandGreen
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer(minLength: 24)

                VStack(spacing: 14) {
                    PlinxBrandLogoView(
                        preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                        accessibilityIdentifier: "signIn.logo.fullColor"
                    )
                    .frame(height: 132)

                    Text("signIn.title")
                        .plinxStyle(theme.typography.title)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white)

                    Text("signIn.tv.subtitle")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .frame(maxWidth: 860)
                        .font(.title3)
                }

                if let pin = viewModel.pin,
                   let authURL = plexAuthURL(pin: pin),
                   let qrCode = qrImage(from: authURL.absoluteString) {
                    VStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(Color.black.opacity(0.38))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                )

                            Image(uiImage: qrCode)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 360, height: 360)
                                .padding(26)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color(white: 0.12))
                                )
                        }
                        .frame(width: 440, height: 440)

                        Text("Scan this code with the Plex app")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.white)

                        VStack(spacing: 4) {
                            Text("Or open this link in your browser")
                                .font(.headline)
                                .foregroundStyle(Color.white.opacity(0.82))

                            Text("plex.tv/link")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.white)
                                .underline()
                        }

                        Button("Refresh Code") {
                            viewModel.cancelSignIn()
                            Task { await viewModel.startSignIn() }
                        }
                        .buttonStyle(PlinkButtonStyle(springs: theme.springs))
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)

                        Text("Waiting for Plex")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 440, height: 440)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color.black.opacity(0.30))
                    )
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
        }
        .onAppear {
            guard !viewModel.isAuthenticating, viewModel.pin == nil else { return }
            Task { await viewModel.startSignIn() }
        }
        .onDisappear {
            viewModel.cancelSignIn()
        }
    }

    private func qrImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL? {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Plinx" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)
    }
}
#endif
