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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.74, green: 0.92, blue: 0.47),
                    Color(red: 0.42, green: 0.79, blue: 0.64),
                    Color(red: 0.22, green: 0.65, blue: 0.63)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 840
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.02), Color.black.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 24)

                VStack(spacing: 18) {
                    PlinxBrandLogoView(
                        preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                        accessibilityIdentifier: "signIn.logo.fullColor",
                        maxWidth: 280
                    )

                    VStack(spacing: 8) {
                        Text("signIn.title")
                            .plinxStyle(theme.typography.title)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.94))

                        Text("signIn.subtitle")
                            .plinxStyle(theme.typography.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.80))
                            .frame(maxWidth: 540)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.16), radius: 20, x: 0, y: 12)
                )

                Button {
                    Task { await viewModel.startSignIn() }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isAuthenticating {
                            ProgressView().tint(Color.white)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 16, weight: .semibold))
                        }

                        Text(viewModel.isAuthenticating
                             ? "signIn.button.waiting"
                             : "signIn.button.continue")
                            .plinxStyle(theme.typography.button)
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
                    )
                }
                .buttonStyle(PlinkButtonStyle(springs: theme.springs))
                .disabled(viewModel.isAuthenticating)
                .opacity(viewModel.isAuthenticating ? 0.78 : 1)
                .accessibilityIdentifier("signIn.primaryButton")
                .accessibilityValue(PlinxBrandingSemantics.signInPrimaryButtonStyleValue)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(theme.palette.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 24)
            }
            .padding(24)
        }
        #endif
    }
}

#if os(tvOS)
extension SignInView {
    private var tvOSBody: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.74, green: 0.92, blue: 0.47),
                    Color(red: 0.42, green: 0.79, blue: 0.64),
                    Color(red: 0.22, green: 0.65, blue: 0.63)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 900
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.04), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 34) {
                Spacer(minLength: 18)

                VStack(spacing: 14) {
                    PlinxBrandLogoView(
                        preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                        accessibilityIdentifier: "signIn.logo.fullColor"
                    )
                    .frame(height: 140)
                    .frame(maxWidth: 360)

                    VStack(spacing: 8) {
                        Text("signIn.title")
                            .plinxStyle(theme.typography.heading)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.92))

                        Text("signIn.tv.subtitle")
                            .plinxStyle(theme.typography.display)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: 1040)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                tvOSSignInSurface

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

    @ViewBuilder
    private var tvOSSignInSurface: some View {
        if let pin = viewModel.pin,
           let authURL = plexAuthURL(pin: pin),
           let qrCode = qrImage(from: authURL.absoluteString) {
            HStack(alignment: .center, spacing: 36) {
                qrCodePanel(qrCode)
                instructionPanel(isAuthenticating: viewModel.isAuthenticating)
            }
            .padding(28)
            .frame(maxWidth: 1240)
            .background(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Color.black.opacity(0.20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 24, x: 0, y: 16)
            )
        } else {
            HStack(alignment: .center, spacing: 36) {
                waitingPanel
                instructionPanel(isAuthenticating: true)
            }
            .padding(28)
            .frame(maxWidth: 1240)
            .background(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Color.black.opacity(0.20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 24, x: 0, y: 16)
            )
        }
    }

    private func qrCodePanel(_ qrCode: UIImage) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.black.opacity(0.46))
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Image(uiImage: qrCode)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 330, height: 330)
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(white: 0.10))
                    )
            }
            .frame(width: 410, height: 410)

            Text("Scan with the Plex app")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))
        }
        .frame(width: 410)
    }

    private var waitingPanel: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.black.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)

                    Text("Waiting for Plex")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 410, height: 410)

            Text("Getting your sign-in code ready")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.82))
        }
        .frame(width: 410)
    }

    private func instructionPanel(isAuthenticating: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in with Plex")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))

                Text("Scan this QR code with your phone to sign in")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("If the app does not open automatically, use plex.tv/link in your browser.")
                    .plinxStyle(theme.typography.body)
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Open in browser")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.62))

                Text("plex.tv/link")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .underline()
            }

            Button {
                viewModel.cancelSignIn()
                Task { await viewModel.startSignIn() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Refresh Code")
                        .plinxStyle(theme.typography.button)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
                )
            }
            .buttonStyle(PlinkButtonStyle(springs: theme.springs))
            .frame(maxWidth: 300, alignment: .leading)
            .accessibilityIdentifier("signIn.refreshButton")
            .disabled(isAuthenticating)
            .opacity(isAuthenticating ? 0.78 : 1)

            if isAuthenticating {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white.opacity(0.8))
                    Text("Waiting for Plex")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
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
