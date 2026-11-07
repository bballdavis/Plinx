import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx-branded profile switcher (replaces Strimr's ProfileSwitcherView)
//
// Functionally identical to Strimr's version but uses Plinx theme colors
// instead of Strimr asset catalog colors (.brandPrimary is already aliased
// in ThemeExtensions.swift).
//
// The only image removed was an asset catalog reference. All SF Symbols
// are preserved.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
struct ProfileSwitcherView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.plinxTheme) private var theme
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: PlexHomeUser?
    @State private var pinInput: String = ""
    @FocusState private var isPinFieldFocused: Bool
    @State private var isShowingLogoutConfirmation = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let profileCardCornerRadius: CGFloat = 24
    private let onClose: (() -> Void)?

    init(viewModel: ProfileSwitcherViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    private var isExpanded: Bool { horizontalSizeClass == .regular }
    private var avatarSize: CGFloat { isExpanded ? 104 : 80 }
    /// Every tile shares one height, whether or not a username is shown.
    private var profileCardHeight: CGFloat { isExpanded ? 216 : 182 }
    /// True during onboarding; false when opened from protected settings.
    private var isOnboarding: Bool { onClose == nil }

    var body: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .hero)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let error = viewModel.errorMessage {
                        errorCard(error)
                            .padding(.top, 20)
                    }
                    profilesGrid
                        .padding(.top, isExpanded ? 36 : 28)
                }
                .padding(.horizontal, isExpanded ? 48 : 24)
                .padding(.top, isExpanded ? 24 : 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 960)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("auth.profile.title")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            chromeHeader
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .task { await viewModel.loadUsers() }
        .plinxRefreshable { await viewModel.loadUsers() }
        .sheet(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            pinPromptContent(for: user)
                #if !os(tvOS)
                .presentationDetents([.medium, .large])
                .presentationBackground(theme.palette.background)
                #endif
        }
        .onChange(of: pinInput) { _, newValue in
            pinInput = String(newValue.filter(\.isNumber).prefix(4))
        }
    }

    // MARK: - Subviews

    /// Plinx chrome in place of the system navigation bar. During onboarding:
    /// log out on the leading edge and progress on the trailing edge. From
    /// settings: log out leading and close trailing.
    private var chromeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            logoutChromeButton
            Spacer(minLength: 0)
            if let onClose {
                PlinxChromeButton(systemImage: "xmark", action: onClose)
            } else {
                PlinxOnboardingStepIndicator(step: .profile, isExpanded: isExpanded)
            }
        }
        .padding(.horizontal, isExpanded ? 48 : PlinxPageHeaderMetrics.horizontalPadding)
        .padding(.top, PlinxPageHeaderMetrics.topPadding)
        .padding(.bottom, PlinxPageHeaderMetrics.bottomPadding)
    }

    private var logoutChromeButton: some View {
        PlinxCompactDestructiveButton(
            systemImage: "rectangle.portrait.and.arrow.right",
            accessibilityLabel: Text("common.actions.logOut", tableName: "Plinx")
        ) {
            isShowingLogoutConfirmation = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("auth.profile.header.title")
                .font(.system(size: isExpanded ? 52 : 36, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Text("auth.profile.header.subtitle")
                .font(.system(isExpanded ? .title3 : .body, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.brandSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: isExpanded ? 190 : 140), spacing: isExpanded ? 18 : 14)],
            spacing: isExpanded ? 18 : 14
        ) {
            if viewModel.users.isEmpty {
                loadingState
            }
            ForEach(viewModel.users) { user in
                profileCard(for: user)
            }
        }
    }

    @ViewBuilder
    private var loadingState: some View {
        if viewModel.isLoading {
            PlinxBrandedLoadingView(
                context: .content,
                titleKey: "auth.profile.loading"
            )
            .frame(maxWidth: .infinity)
        } else {
            Text("auth.profile.empty")
                .foregroundStyle(Color.brandSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private func profileCard(for user: PlexHomeUser) -> some View {
        let isSelected = viewModel.activeUserUUID == user.uuid
        let isProtected = user.protected ?? false
        let subtitle = profileSubtitle(for: user)

        return Button {
            if isProtected {
                pinPromptUser = user
                pinInput = ""
                isPinFieldFocused = true
            } else {
                Task { await viewModel.switchToUser(user, pin: nil) }
            }
        } label: {
            VStack(spacing: 12) {
                avatarView(for: user)
                    .frame(width: avatarSize, height: avatarSize)

                VStack(spacing: 3) {
                    Text(user.friendlyName ?? user.title ?? "?")
                        .font(.system(isExpanded ? .title3 : .headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(subtitle.isEmpty ? 0 : 1)
                        .accessibilityHidden(subtitle.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: profileCardHeight)
            .background(profileCardBackground(isSelected: isSelected))
            .overlay(profileCardBorder(isSelected: isSelected))
            .overlay(alignment: .topTrailing) {
                profileStatusBadge(isSelected: isSelected, isProtected: isProtected)
            }
            .contentShape(RoundedRectangle(cornerRadius: profileCardCornerRadius, style: .continuous))
            .animation(theme.springs.interactive, value: isSelected)
        }
        .buttonStyle(PlinkButtonStyle(springs: theme.springs))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(
            isProtected ? Text("auth.profile.pin.required") : Text("")
        )
    }

    private func avatarView(for user: PlexHomeUser) -> some View {
        ZStack {
            if let url = user.thumb {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderAvatar
                }
            } else {
                placeholderAvatar
            }
        }
        .clipShape(Circle())
        .overlay {
            if viewModel.switchingUserUUID == user.uuid {
                Circle()
                    .fill(Color.black.opacity(0.35))
                ProgressView().tint(Color.accentColor)
            }
        }
    }

    private func profileCardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: profileCardCornerRadius, style: .continuous)
            .fill(PlinxBrand.surface)
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.28) : Color.black.opacity(0.28),
                radius: isSelected ? 18 : 12,
                x: 0,
                y: isSelected ? 8 : 6
            )
    }

    private func profileCardBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: profileCardCornerRadius, style: .continuous)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.white.opacity(0.08),
                lineWidth: isSelected ? 2.5 : 1
            )
    }

    @ViewBuilder
    private func profileStatusBadge(isSelected: Bool, isProtected: Bool) -> some View {
        if isProtected {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .padding(10)
                .accessibilityHidden(true)
        } else if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(PlinxBrand.shell)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
                .padding(10)
                .accessibilityHidden(true)
        }
    }

    private func profileSubtitle(for user: PlexHomeUser) -> String {
        user.username ?? user.email ?? ""
    }

    private var placeholderAvatar: some View {
        PlinxBrand.gradient
            .overlay(
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(PlinxBrand.shell.opacity(0.85))
                    .padding(avatarSize * 0.26)
            )
    }

    private func pinPromptContent(for user: PlexHomeUser) -> some View {
        let displayName = user.friendlyName ?? user.title ?? "?"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("auth.profile.pin.title")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("auth.profile.pin.prompt \(displayName)")
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                PlinxChromeButton(systemImage: "xmark") {
                    resetPinPrompt()
                }
            }

            SecureField("auth.profile.pin.placeholder", text: $pinInput)
                #if !os(tvOS)
                .keyboardType(.numberPad)
                #endif
                .textContentType(.password)
                .focused($isPinFieldFocused)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(isPinFieldFocused ? 0.8 : 0.35), lineWidth: 1)
                )

            Button {
                let enteredPin = pinInput
                Task { await viewModel.switchToUser(user, pin: enteredPin) }
                resetPinPrompt()
            } label: {
                Text("common.actions.switchProfile")
            }
            .buttonStyle(PlinxActionButtonStyle())
            .disabled(pinInput.count < 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PlinxPageHeaderMetrics.horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.palette.background.ignoresSafeArea())
        .tint(.accentColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("auth.profile.pin.required"))
        .onAppear { isPinFieldFocused = true }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .foregroundStyle(.white)
            Button {
                Task { await viewModel.loadUsers() }
            } label: {
                Text("common.actions.retry")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(theme.palette.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding()
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resetPinPrompt() {
        pinPromptUser = nil
        pinInput = ""
        isPinFieldFocused = false
    }
}
