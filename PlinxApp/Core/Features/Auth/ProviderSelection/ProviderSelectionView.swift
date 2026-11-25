import PlinxUI
import SwiftUI

/// First step of account setup on the Plinx quiet shell: a grown-up connects
/// the family's Plex account or Jellyfin server. At first launch on iPhone and
/// iPad, the sign-in information sheet also offers the sample library.
struct ProviderSelectionView: View {
    @Environment(SessionManager.self) private var sessionManager
    #if os(tvOS)
    @FocusState private var focusedProvider: MediaProvider?
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingInformation = false
    @State private var launchDemoAfterInformation = false
    #endif
    @State private var isLaunchingDemo = false
    @State private var demoLaunchFailed = false

    let onSelect: (MediaProvider) -> Void
    /// First launch only: login help and the sample library entry.
    var offersSampleLibrary = false
    /// Adding a connection from Settings or a profile can be abandoned.
    var onCancel: (() -> Void)?

    var body: some View {
        content
            #if !os(tvOS)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingInformation, onDismiss: {
                guard launchDemoAfterInformation else { return }
                launchDemoAfterInformation = false
                launchDemo()
            }) {
                PlinxSignInInformationSheet(
                    isDemoDisabled: isLaunchingDemo,
                    onExploreDemo: {
                        launchDemoAfterInformation = true
                        isShowingInformation = false
                    },
                    onDone: { isShowingInformation = false }
                )
            }
            #endif
            .accessibilityIdentifier("providerSelection")
    }

    // MARK: - iPhone and iPad

    #if !os(tvOS)
    private var content: some View {
        GeometryReader { proxy in
            let layout = PlinxOnboardingLayout(width: proxy.size.width, height: proxy.size.height)
            let isExpanded = layout != .compact

            ZStack {
                PlinxAmbientBackground(intensity: .hero)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 12) {
                            if let onCancel {
                                PlinxChromeButton(systemImage: "xmark", action: onCancel)
                                    .accessibilityLabel(Text("common.actions.cancel", tableName: "Plinx"))
                                    .accessibilityIdentifier("providerSelection.cancel")
                            }
                            PlinxBrandLogoView(
                                asset: .lockupOnDark,
                                accessibilityIdentifier: "providerSelection.logo",
                                maxWidth: layout.logoWidth
                            )
                            Spacer(minLength: 16)
                            PlinxOnboardingStepIndicator(step: .connect, isExpanded: isExpanded)
                        }
                        .padding(.top, isExpanded ? 32 : 12)

                        Spacer(minLength: isExpanded ? 48 : 56)

                        VStack(alignment: .leading, spacing: 14) {
                            PlinxOnboardingGrownUpEyebrow(isExpanded: isExpanded)

                            Text(Self.title)
                                .font(.system(size: layout.titleSize, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.white)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("providerSelection.title")

                            Text(Self.subtitle)
                                .font(.system(isExpanded ? .title2 : .title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.brandSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        providerButtons(minHeight: isExpanded ? 70 : 84)
                            .frame(maxWidth: 460)
                            .padding(.top, 40)

                        sampleLibraryFooter
                            .frame(maxWidth: 460)
                            .padding(.top, 18)
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.bottom, isExpanded ? 40 : 24)
                    .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func providerButtons(minHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            Button {
                onSelect(.plex)
            } label: {
                Label {
                    Text("signIn.button.continue")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } icon: {
                    Image(systemName: "play.rectangle.fill")
                }
            }
            .buttonStyle(PlinxActionButtonStyle(treatment: .primary, minHeight: minHeight))
            .disabled(isLaunchingDemo)
            .accessibilityIdentifier("provider.plex")

            Button {
                onSelect(.jellyfin)
            } label: {
                Label {
                    Text(Self.jellyfinTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } icon: {
                    Image(systemName: "server.rack")
                }
            }
            .buttonStyle(PlinxActionButtonStyle(treatment: .secondary))
            .disabled(isLaunchingDemo)
            .accessibilityIdentifier("provider.jellyfin")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var sampleLibraryFooter: some View {
        if offersSampleLibrary {
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text(Self.helpLabel)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PlinxSignInInformationButton(isCompact: true) {
                        isShowingInformation = true
                    }
                    .disabled(isLaunchingDemo)
                }
                if isLaunchingDemo {
                    ProgressView()
                        .accessibilityLabel(Text("signIn.demo.loading", tableName: "Plinx"))
                }
                if demoLaunchFailed {
                    Text("signIn.demo.failed", tableName: "Plinx")
                        .font(.callout)
                        .foregroundStyle(Color.brandSecondary)
                        .accessibilityIdentifier("signIn.demoError")
                }
            }
        }
    }
    #endif

    // MARK: - Apple TV

    #if os(tvOS)
    private var content: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .hero)

            VStack(spacing: 40) {
                PlinxBrandLogoView(
                    asset: .lockupWhite,
                    accessibilityIdentifier: "providerSelection.logo",
                    maxWidth: 390
                )
                .frame(height: 130)

                VStack(spacing: 14) {
                    PlinxOnboardingGrownUpEyebrow(isExpanded: true)
                    Text(Self.title)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("providerSelection.title")
                    Text(Self.subtitle)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1_100)
                }

                HStack(spacing: 48) {
                    providerCard(
                        title: Text("provider.plex"),
                        systemImage: "play.rectangle.fill",
                        provider: .plex
                    )
                    providerCard(
                        title: Text("provider.jellyfin"),
                        systemImage: "server.rack",
                        provider: .jellyfin
                    )
                }
                .focusSection()

                if let onCancel {
                    Button(action: onCancel) {
                        Text("common.actions.cancel", tableName: "Plinx")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 420, height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(PlinxBrand.surface)
                            )
                    }
                    .plinxTVFocusButton(style: PlinxFocusSurfaceStyle(cornerRadius: 18, focusedFillOpacity: 0.08))
                    .accessibilityIdentifier("providerSelection.cancel")
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .defaultFocus($focusedProvider, .plex)
    }

    private func providerCard(title: Text, systemImage: String, provider: MediaProvider) -> some View {
        Button {
            onSelect(provider)
        } label: {
            VStack(spacing: 24) {
                Image(systemName: systemImage)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                title
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 420, height: 260)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(PlinxBrand.surface)
            )
        }
        .focused($focusedProvider, equals: provider)
        .plinxTVFocusButton(
            style: PlinxFocusSurfaceStyle(
                focusedScale: 1.04,
                focusedShadowRadius: 22,
                cornerRadius: 28,
                focusedFillOpacity: 0.1
            )
        )
        .accessibilityIdentifier("provider.\(provider.rawValue)")
    }
    #endif

    // MARK: - Sample library

    private func launchDemo() {
        guard !isLaunchingDemo else { return }
        isLaunchingDemo = true
        demoLaunchFailed = false
        Task { @MainActor in
            await DemoFixtureBootstrap.start(sessionManager: sessionManager)
            demoLaunchFailed = sessionManager.status != .ready
            isLaunchingDemo = false
        }
    }

    // MARK: - Copy

    static var title: String {
        String(
            localized: "provider.plinx.title",
            defaultValue: "Connect your family’s videos",
            table: "Plinx"
        )
    }

    static var subtitle: String {
        String(
            localized: "provider.plinx.subtitle",
            defaultValue: "Use the Plex account or Jellyfin server your family already has. You’ll choose who’s watching next.",
            table: "Plinx"
        )
    }

    static var jellyfinTitle: String {
        String(
            localized: "provider.plinx.jellyfin",
            defaultValue: "Use a Jellyfin server",
            table: "Plinx"
        )
    }

    static var helpLabel: String {
        String(
            localized: "provider.plinx.help",
            defaultValue: "Sign-in help and the sample library",
            table: "Plinx"
        )
    }
}
