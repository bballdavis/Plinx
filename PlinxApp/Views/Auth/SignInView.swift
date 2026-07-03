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
    @FocusState private var focusedRefreshAction: Bool
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
    private var tvOSPanelHeight: CGFloat { 410 }
    private var tvOSPanelWidth: CGFloat { 410 }

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

                PlinxBrandLogoView(
                    preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                    accessibilityIdentifier: "signIn.logo.fullColor",
                    maxWidth: 480
                )
                .frame(height: 210)

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
            if !viewModel.isAuthenticating, viewModel.pin == nil {
                Task { await viewModel.startSignIn() }
            }
            focusedRefreshAction = true
        }
        .onDisappear {
            viewModel.cancelSignIn()
        }
    }

    @ViewBuilder
    private var tvOSSignInSurface: some View {
        let pin = viewModel.pin
        let qrCode = pin.flatMap { plexAuthURL(pin: $0) }
            .flatMap { qrImage(from: $0.absoluteString) }

        HStack(alignment: .center, spacing: 30) {
            qrCodePlate(qrCode)
            instructionPanel(isAuthenticating: viewModel.isAuthenticating)
        }
        .padding(28)
        .frame(maxWidth: 1240)
        .background(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 16)
        )
    }

    private func qrCodePlate(_ qrCode: UIImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )

            if let qrCode {
                Image(uiImage: qrCode)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(18)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.black.opacity(0.65))
            }
        }
        .frame(width: tvOSPanelWidth, height: tvOSPanelHeight)
    }

    private func instructionPanel(isAuthenticating: Bool) -> some View {
        VStack(alignment: .center, spacing: 18) {
            Text("signIn.title")
                .font(.system(size: 50, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

            Spacer(minLength: 8)

            Text("Scan this QR code with your phone to sign in to Plex.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.90))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 18)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white.opacity(0.9))
                    }
                    Text("Waiting for Plex")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Button {
                    viewModel.cancelSignIn()
                    Task { await viewModel.startSignIn() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Refresh Code")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: 360, minHeight: 66)
                    .padding(.horizontal, 20)
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
                .focused($focusedRefreshAction)
                .accessibilityIdentifier("signIn.refreshButton")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 540, height: tvOSPanelHeight)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
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
