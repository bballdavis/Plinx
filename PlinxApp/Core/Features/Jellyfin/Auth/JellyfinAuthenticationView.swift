import PlinxUI
import SwiftUI

/// The Jellyfin step of account setup: the server address, then the user's
/// credentials or Quick Connect. It uses the Plinx onboarding shell of the Plex
/// sign-in (`SignInView`): the ambient background, the Plinx lockup, the
/// grown-up eyebrow and step indicator on iPhone and iPad, and the shared
/// onboarding actions.
struct JellyfinAuthenticationView: View {
    @State private var viewModel: JellyfinAuthenticationViewModel
    #if !os(tvOS)
    /// True when pushed by account setup or presented to reconnect: the back control can leave the screen.
    @Environment(\.isPresented) private var isPresented
    #endif

    init(viewModel: JellyfinAuthenticationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .onDisappear { viewModel.cancelQuickConnect() }
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
                            if viewModel.step == .credentials {
                                PlinxOnboardingBackButton { viewModel.goBack() }
                                    .disabled(viewModel.isLoading)
                            } else if isPresented {
                                PlinxOnboardingBackButton()
                            }
                            PlinxBrandLogoView(
                                asset: .lockupOnDark,
                                accessibilityIdentifier: "jellyfin.auth.logo",
                                maxWidth: layout.logoWidth
                            )
                            Spacer(minLength: 16)
                            PlinxOnboardingStepIndicator(step: .connect, isExpanded: isExpanded)
                        }
                        .padding(.top, isExpanded ? 32 : 12)

                        Spacer(minLength: isExpanded ? 48 : 56)

                        VStack(alignment: .leading, spacing: 14) {
                            PlinxOnboardingGrownUpEyebrow(isExpanded: isExpanded)

                            title
                                .font(.system(size: layout.titleSize, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.white)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)

                            subtitle
                                .font(.system(isExpanded ? .title2 : .title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.brandSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        form
                            .frame(maxWidth: 460)
                            .padding(.top, 40)
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
        .toolbar(.hidden, for: .navigationBar)
    }
    #endif

    // MARK: - Apple TV

    #if os(tvOS)
    private var content: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .hero)

            ScrollView {
                VStack(spacing: 40) {
                    PlinxBrandLogoView(
                        asset: .lockupWhite,
                        accessibilityIdentifier: "jellyfin.auth.logo",
                        maxWidth: 390
                    )
                    .frame(height: 130)

                    VStack(spacing: 14) {
                        PlinxOnboardingGrownUpEyebrow(isExpanded: true)
                        title
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        subtitle
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 1_100)
                    }

                    form
                        .frame(maxWidth: 640)

                    if viewModel.step == .credentials {
                        PlinxOnboardingActionButton(treatment: .secondary) {
                            viewModel.goBack()
                        } label: {
                            Label {
                                Text("common.actions.back", tableName: "Plinx")
                            } icon: {
                                Image(systemName: "chevron.left")
                            }
                        }
                        .disabled(viewModel.isLoading)
                        .accessibilityIdentifier("onboarding.back")
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
        }
    }
    #endif

    // MARK: - Shared content

    @ViewBuilder
    private var title: some View {
        if viewModel.step == .server {
            Text("jellyfin.auth.server.title")
        } else {
            Text("jellyfin.auth.credentials.title")
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if viewModel.step == .server {
            Text("jellyfin.auth.server.subtitle")
        } else {
            Text("jellyfin.auth.credentials.subtitle \(viewModel.serverName)")
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            fields

            if let errorMessage = viewModel.errorMessage {
                PlinxOnboardingErrorMessage(message: errorMessage, accessibilityIdentifier: "jellyfin.auth.error")
            }

            actions

            if viewModel.step == .server, !viewModel.discoveredServers.isEmpty {
                discoveredServersList
            }

            if viewModel.step == .credentials, viewModel.isQuickConnectAvailable {
                quickConnect
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var fields: some View {
        if viewModel.step == .server {
            TextField("jellyfin.auth.server.placeholder", text: Bindable(viewModel).serverURL)
                .textContentType(.URL)
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            #endif
                .onSubmit { Task { await viewModel.validateServer() } }
                .plinxOnboardingFieldStyle()
                .accessibilityIdentifier("jellyfin.auth.server")
        } else {
            TextField("jellyfin.auth.username", text: Bindable(viewModel).username)
                .textContentType(.username)
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            #endif
                .plinxOnboardingFieldStyle()
                .accessibilityIdentifier("jellyfin.auth.username")
            SecureField("jellyfin.auth.password", text: Bindable(viewModel).password)
                .textContentType(.password)
                .onSubmit { Task { await viewModel.signIn() } }
                .plinxOnboardingFieldStyle()
                .accessibilityIdentifier("jellyfin.auth.password")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if viewModel.step == .server {
            primaryAction("common.actions.continue", isLoading: viewModel.isLoading) {
                Task { await viewModel.validateServer() }
            }
            .disabled(viewModel.isBusy || viewModel.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("jellyfin.auth.continue")

            // Hidden where the build cannot broadcast (iPhone and iPad without
            // the multicast entitlement): there, every search would fail.
            if viewModel.isDiscoveryAvailable {
                PlinxOnboardingActionButton(treatment: .secondary) {
                    Task { await viewModel.discoverServers() }
                } label: {
                    Label {
                        Text("jellyfin.auth.discovery.search")
                    } icon: {
                        if viewModel.isDiscovering {
                            ProgressView()
                                .tint(Color.accentColor)
                        } else {
                            Image(systemName: "network")
                        }
                    }
                }
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier("jellyfin.auth.discover")
            }
        } else {
            primaryAction("jellyfin.auth.signIn", isLoading: viewModel.isLoading) {
                Task { await viewModel.signIn() }
            }
            .disabled(viewModel.isBusy || viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("jellyfin.auth.signIn")
        }
    }

    private func primaryAction(
        _ title: LocalizedStringKey,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PlinxOnboardingActionButton(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .tint(Color.white)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    @ViewBuilder
    private var quickConnect: some View {
        if let code = viewModel.quickConnectCode {
            VStack(spacing: 12) {
                Text("jellyfin.auth.quickConnect.instructions")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.brandSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: code)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .foregroundStyle(Color.white)
                #if !os(tvOS)
                    .textSelection(.enabled)
                #endif
                    .accessibilityIdentifier("jellyfin.auth.quickConnect.code")
                PlinxOnboardingActionButton(treatment: .secondary) {
                    viewModel.cancelQuickConnect()
                } label: {
                    Text("common.actions.cancel")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PlinxBrand.surface)
            )
        } else {
            PlinxOnboardingActionButton(treatment: .secondary) {
                viewModel.startQuickConnect()
            } label: {
                Label {
                    Text("jellyfin.auth.quickConnect.button")
                } icon: {
                    Image(systemName: "qrcode")
                }
            }
            .disabled(viewModel.isBusy)
            .accessibilityIdentifier("jellyfin.auth.quickConnect")
        }
    }

    private var discoveredServersList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.discoveredServers) { server in
                Button {
                    Task { await viewModel.selectDiscoveredServer(server) }
                } label: {
                    HStack(spacing: Self.serverRowSpacing) {
                        Image(systemName: "server.rack")
                            .font(.system(size: Self.serverIconSize * 0.45, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: Self.serverIconSize, height: Self.serverIconSize)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text(server.url.absoluteString)
                                .font(.system(.footnote, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.brandSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.brandSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(Self.serverRowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(PlinxBrand.surface)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                #if os(tvOS)
                .plinxTVFocusButton(style: PlinxFocusSurfaceStyle(cornerRadius: 20, focusedFillOpacity: 0.12))
                #else
                .buttonStyle(.plain)
                #endif
                .disabled(viewModel.isBusy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jellyfin.auth.discoveredServers")
    }

    #if os(tvOS)
    private static let serverIconSize: CGFloat = 64
    private static let serverRowSpacing: CGFloat = 28
    private static let serverRowPadding: CGFloat = 24
    #else
    private static let serverIconSize: CGFloat = 44
    private static let serverRowSpacing: CGFloat = 12
    private static let serverRowPadding: CGFloat = 16
    #endif
}

private extension View {
    /// A text field on the dark onboarding shell. Apple TV keeps the system field, which owns its focus treatment.
    func plinxOnboardingFieldStyle() -> some View {
        #if os(tvOS)
        textFieldStyle(.automatic)
        #else
        textFieldStyle(.plain)
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.white)
            .tint(Color.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PlinxBrand.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        #endif
    }
}
