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
            let layout = PlinxOnboardingLayout(width: proxy.size.width)

            ZStack {
                PlinxAmbientBackground(intensity: .hero)

                ScrollView {
                    quietShell(layout: layout)
                        .frame(maxWidth: layout.contentMaxWidth)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onDisappear {
            viewModel.cancelSignIn()
        }
        #endif
    }

    #if !os(tvOS)
    // MARK: - Quiet shell (iPhone and iPad)

    /// Sign-in on the ambient dark shell: logo and step indicator on top,
    /// left-aligned headline, and the app's glass primary action. Wide iPad
    /// layouts add a "What happens next" card beside the copy.
    private func quietShell(layout: PlinxOnboardingLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                PlinxBrandLogoView(
                    asset: .lockupOnDark,
                    accessibilityIdentifier: "signIn.logo.fullColor",
                    maxWidth: layout.logoWidth
                )
                Spacer(minLength: 16)
                PlinxOnboardingStepIndicator(step: .connect, isExpanded: layout != .compact)
            }
            .padding(.top, layout == .compact ? 12 : 32)

            Spacer(minLength: layout == .compact ? 56 : 48)

            switch layout {
            case .wide:
                HStack(alignment: .center, spacing: 72) {
                    VStack(alignment: .leading, spacing: 0) {
                        headline(layout: layout)
                        actionArea(layout: layout)
                            .frame(maxWidth: 420)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PlinxOnboardingNextStepsCard(currentStep: .connect)
                        .frame(maxWidth: 460)
                }
                Spacer(minLength: 48)
            case .regular:
                headline(layout: layout)
                PlinxOnboardingNextStepsCard(currentStep: .connect)
                    .padding(.top, 36)
                Spacer(minLength: 36)
                actionArea(layout: layout)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
            case .compact:
                headline(layout: layout)
                Spacer(minLength: 40)
                actionArea(layout: layout)
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout == .compact ? 24 : 40)
        .accessibilityElement(children: .contain)
    }

    private func headline(layout: PlinxOnboardingLayout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PlinxOnboardingGrownUpEyebrow(isExpanded: layout != .compact)

            Text("signIn.portal.title", tableName: "Plinx")
                .font(.system(size: layout.titleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("signIn.portal.title")

            Text("signIn.portal.subtitle", tableName: "Plinx")
                .font(.system(layout == .compact ? .title3 : .title2, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.brandSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionArea(layout: PlinxOnboardingLayout) -> some View {
        VStack(spacing: 14) {
            if let error = viewModel.errorMessage {
                Label {
                    Text(error)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                }
                .foregroundStyle(Color.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PlinxBrand.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                )
                .accessibilityIdentifier("signIn.error")
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
                            .font(.system(size: 22, weight: .semibold))
                    }

                    Text(
                        viewModel.isAuthenticating
                            ? "signIn.button.waiting"
                            : "signIn.button.continue"
                    )
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
            }
            .buttonStyle(PlinxActionButtonStyle(treatment: .primary, minHeight: layout == .compact ? 64 : 70))
            .disabled(viewModel.isAuthenticating)
            .accessibilityIdentifier("signIn.primaryButton")
            .accessibilityValue(PlinxBrandingSemantics.signInPrimaryButtonStyleValue)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") {
                    viewModel.cancelSignIn()
                }
                .buttonStyle(PlinxActionButtonStyle(treatment: .secondary))
                .accessibilityIdentifier("signIn.cancelButton")
            } else {
                Text("signIn.footnote", tableName: "Plinx")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            PlinxAmbientBackground(intensity: .hero)

            VStack(spacing: 28) {
                PlinxBrandLogoView(
                    asset: .lockupOnDark,
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
                        PlinxBrand.lime,
                        PlinxBrand.teal,
                        PlinxBrand.teal.opacity(0.74),
                        PlinxBrand.charcoal
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
        PlexAuthURLBuilder.url(
            clientIdentifier: pin.clientIdentifier,
            code: pin.code,
            productName: PlexProductIdentity.name
        )
    }
}
#endif
