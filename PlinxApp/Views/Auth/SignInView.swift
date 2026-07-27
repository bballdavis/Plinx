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
        GeometryReader { proxy in
            ZStack {
                if proxy.size.width >= 700 {
                    portalBackground(expandedLayout: true)
                        .ignoresSafeArea()
                } else {
                    Color.appBackground
                        .ignoresSafeArea()
                }

                RadialGradient(
                    colors: [
                        Color(red: 0.13, green: 0.42, blue: 0.32).opacity(0.24),
                        .clear
                    ],
                    center: .top,
                    startRadius: 20,
                    endRadius: 520
                )
                .ignoresSafeArea()

                ScrollView {
                    let expandedLayout = proxy.size.width >= 700

                    guidedPortal(expandedLayout: expandedLayout)
                        .frame(
                            maxWidth: expandedLayout ? .infinity : 620,
                            minHeight: max(680, proxy.size.height - 28)
                        )
                        .padding(.horizontal, expandedLayout ? 0 : 28)
                        .padding(.vertical, expandedLayout ? 0 : 14)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        #endif
    }

    #if !os(tvOS)
    private func guidedPortal(expandedLayout: Bool) -> some View {
        VStack(spacing: 0) {
            PlinxBrandLogoView(
                preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                accessibilityIdentifier: "signIn.logo.fullColor",
                maxWidth: expandedLayout ? 280 : 220
            )
            .padding(.top, expandedLayout ? 64 : 96)

            Spacer()
                .frame(height: expandedLayout ? 52 : 108)

            VStack(spacing: 18) {
                Label {
                    Text("signIn.grownUpStep", tableName: "Plinx")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.02, green: 0.36, blue: 0.34))
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.76, green: 0.97, blue: 0.77))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                )
                .accessibilityIdentifier("signIn.grownUpStep")
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .lineLimit(1)

                Text("signIn.portal.title", tableName: "Plinx")
                    .font(.system(size: expandedLayout ? 52 : 39, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: expandedLayout ? 680 : 430)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("signIn.portal.title")

                Text("signIn.portal.subtitle", tableName: "Plinx")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.65, green: 0.94, blue: 0.76))
                    .frame(maxWidth: expandedLayout ? 680 : 430)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, expandedLayout ? 64 : 28)

            Spacer(minLength: expandedLayout ? 32 : 44)

            if let error = viewModel.errorMessage {
                Label {
                    Text(error)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, expandedLayout ? 64 : 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack(spacing: 12) {
                    if viewModel.isAuthenticating {
                        ProgressView()
                            .tint(Color.white)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 28, weight: .semibold))
                    }

                    Text(
                        viewModel.isAuthenticating
                            ? "signIn.button.waiting"
                            : "signIn.button.continue"
                    )
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.75)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: expandedLayout ? 104 : 90)
                .padding(.horizontal, expandedLayout ? 48 : 20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.10, green: 0.49, blue: 0.38),
                                    Color(red: 0.025, green: 0.28, blue: 0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.88), lineWidth: 1.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                        .padding(1)
                )
                .shadow(color: Color.accentColor.opacity(0.28), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(PlinkButtonStyle(springs: theme.springs))
            .disabled(viewModel.isAuthenticating)
            .opacity(viewModel.isAuthenticating ? 0.78 : 1)
            .accessibilityIdentifier("signIn.primaryButton")
            .accessibilityValue(PlinxBrandingSemantics.signInPrimaryButtonStyleValue)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, expandedLayout ? 64 : 16)
            .padding(.bottom, viewModel.isAuthenticating ? 0 : (expandedLayout ? 48 : 56))

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") {
                    viewModel.cancelSignIn()
                }
                .foregroundStyle(Color.white.opacity(0.86))
                .padding(.top, 16)
                .padding(.bottom, expandedLayout ? 48 : 56)
                .accessibilityIdentifier("signIn.cancelButton")
            }
        }
        .background {
            portalBackground(expandedLayout: expandedLayout)
        }
        .accessibilityElement(children: .contain)
        .onDisappear {
            viewModel.cancelSignIn()
        }
    }

    @ViewBuilder
    private func portalBackground(expandedLayout: Bool) -> some View {
        let gradient = LinearGradient(
            colors: [
                Color(red: 0.69, green: 0.88, blue: 0.43),
                Color(red: 0.15, green: 0.61, blue: 0.47),
                Color(red: 0.02, green: 0.39, blue: 0.39),
                Color(red: 0.02, green: 0.17, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        if expandedLayout {
            gradient
                .overlay(
                    RadialGradient(
                        colors: [Color.white.opacity(0.18), .clear],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 720
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.18), .clear],
                                center: .topLeading,
                                startRadius: 20,
                                endRadius: 480
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.78, green: 1.0, blue: 0.54),
                                    Color.accentColor.opacity(0.84)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.accentColor.opacity(0.26), radius: 24, x: 0, y: 10)
        }
    }
    #endif
}

#if os(tvOS)
extension SignInView {
    private var tvOSPanelHeight: CGFloat { 430 }
    private var tvOSPanelWidth: CGFloat { 430 }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    private var tvOSBody: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.43, blue: 0.31).opacity(0.32),
                    .clear
                ],
                center: .top,
                startRadius: 80,
                endRadius: 1_100
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 900
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                PlinxBrandLogoView(
                    preferredAssetName: PlinxBrandingSemantics.fullColorLogoAssetName,
                    accessibilityIdentifier: "signIn.logo.fullColor",
                    maxWidth: 390
                )
                .frame(height: 130)

                tvOSSignInSurface
            }
            .padding(.horizontal, 70)
            .padding(.top, 46)
            .padding(.bottom, 54)
            .frame(maxWidth: 1_590, maxHeight: 940)
            .background(tvOSPortalBackground)
        }
        .onAppear {
            if !isUITesting, !viewModel.isAuthenticating, viewModel.pin == nil {
                Task { await viewModel.startSignIn() }
            }
            Task { @MainActor in
                await Task.yield()
                focusedRefreshAction = true
            }
        }
        .onDisappear {
            viewModel.cancelSignIn()
        }
    }

    @ViewBuilder
    private var tvOSSignInSurface: some View {
        let pin = viewModel.pin
        let liveQRCode = pin.flatMap { plexAuthURL(pin: $0) }
            .flatMap { qrImage(from: $0.absoluteString) }
        let qrCode = liveQRCode ?? (
            isUITesting
                ? qrImage(from: "PLINX UI TEST SIGN-IN PREVIEW")
                : nil
        )

        HStack(alignment: .center, spacing: 64) {
            qrCodePlate(qrCode)
            instructionPanel(isAuthenticating: viewModel.isAuthenticating)
        }
        .frame(maxWidth: 1_410)
    }

    private func qrCodePlate(_ qrCode: UIImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)

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
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text("signIn.grownUpStep", tableName: "Plinx")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.02, green: 0.36, blue: 0.34))
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.76, green: 0.97, blue: 0.77))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 2)
            )
            .accessibilityIdentifier("signIn.grownUpStep")

            Text("signIn.portal.title", tableName: "Plinx")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .accessibilityIdentifier("signIn.portal.title")

            Text("auth.signIn.qr.instructions", tableName: "Plinx")
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Text("signIn.portal.subtitle", tableName: "Plinx")
                .font(.system(size: 25, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.68, green: 0.95, blue: 0.78))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if let error = viewModel.errorMessage {
                Label {
                    Text(error)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                )
                .padding(.top, 18)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white.opacity(0.9))
                    }
                    Text("auth.signIn.waiting", tableName: "Plinx")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.88))
                }
                .frame(minHeight: 30)

                refreshCodeButton
            }
            .padding(.top, 32)
        }
        .frame(width: 700, alignment: .leading)
    }

    private var refreshCodeButton: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 28, weight: .bold))
            Text("auth.signIn.refreshCode", tableName: "Plinx")
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.white)
        .frame(width: 560, height: 82)
        .background(refreshButtonBackground)
        .overlay(refreshButtonFocusRing)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .scaleEffect(focusedRefreshAction ? 1.018 : 1)
        .shadow(
            color: Color.accentColor.opacity(focusedRefreshAction ? 0.42 : 0.14),
            radius: focusedRefreshAction ? 14 : 8,
            x: 0,
            y: focusedRefreshAction ? 7 : 4
        )
        .focusable(interactions: .activate)
        .focused($focusedRefreshAction)
        .defaultFocus($focusedRefreshAction, true)
        .focusEffectDisabled()
        .onTapGesture {
            viewModel.cancelSignIn()
            Task { await viewModel.startSignIn() }
        }
        .animation(.easeOut(duration: 0.16), value: focusedRefreshAction)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("signIn.refreshButton")
        .accessibilityValue(focusedRefreshAction ? "focused" : "not focused")
    }

    private var refreshButtonBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.49, blue: 0.38),
                        Color(red: 0.025, green: 0.28, blue: 0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.72), lineWidth: 2)
            )
    }

    private var refreshButtonFocusRing: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
                focusedRefreshAction ? Color.white.opacity(0.98) : Color.clear,
                lineWidth: 4
            )
            .padding(5)
    }

    private var tvOSPortalBackground: some View {
        RoundedRectangle(cornerRadius: 58, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.69, green: 0.88, blue: 0.43),
                        Color(red: 0.15, green: 0.61, blue: 0.47),
                        Color(red: 0.02, green: 0.39, blue: 0.39),
                        Color(red: 0.02, green: 0.17, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 58, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.18), .clear],
                            center: .topLeading,
                            startRadius: 60,
                            endRadius: 880
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 58, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.78, green: 1.0, blue: 0.54),
                                Color.accentColor.opacity(0.84)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 3
                    )
            )
            .shadow(color: Color.accentColor.opacity(0.30), radius: 38, x: 0, y: 18)
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
