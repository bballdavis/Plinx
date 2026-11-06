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

    private let profileCardCornerRadius: CGFloat = 26
    private let profileCardAvatarSize: CGFloat = 120
    private let profileCardMinHeight: CGFloat = 228
    private let onClose: (() -> Void)?

    init(viewModel: ProfileSwitcherViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    if let error = viewModel.errorMessage {
                        errorCard(error)
                    }
                    profilesGrid
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
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

    /// Plinx chrome in place of the system navigation bar: log out on the
    /// leading edge and, when presented as a sheet, close on the trailing edge.
    private var chromeHeader: some View {
        HStack(spacing: 12) {
            if onClose != nil {
                logoutChromeButton
            }
            Spacer(minLength: 0)
            if let onClose {
                PlinxChromeButton(systemImage: "xmark", action: onClose)
            } else {
                logoutChromeButton
            }
        }
        .padding(.horizontal, PlinxPageHeaderMetrics.horizontalPadding)
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
        VStack(spacing: 8) {
            Text("auth.profile.header.title")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("auth.profile.header.subtitle")
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 18)], spacing: 18) {
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
                .foregroundStyle(.white.opacity(0.7))
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
            VStack(alignment: .leading, spacing: 14) {
                avatarView(for: user)
                    .frame(width: profileCardAvatarSize, height: profileCardAvatarSize)
                    .overlay(alignment: .topTrailing) {
                        profileStatusBadge(isSelected: isSelected, isProtected: isProtected)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.friendlyName ?? user.title ?? "?")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .opacity(subtitle.isEmpty ? 0 : 1)
                            .accessibilityHidden(subtitle.isEmpty)
                    }
                    .frame(height: 36, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: profileCardMinHeight, alignment: .top)
            .padding(16)
            .background(profileCardBackground(isSelected: isSelected))
            .overlay(profileCardBorder(isSelected: isSelected))
            .contentShape(RoundedRectangle(cornerRadius: profileCardCornerRadius, style: .continuous))
            .animation(theme.springs.interactive, value: isSelected)
        }
        .buttonStyle(.plain)
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if viewModel.switchingUserUUID == user.uuid {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                ProgressView().tint(theme.palette.primary)
            }
        }
    }

    private func profileCardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: profileCardCornerRadius, style: .continuous)
            .fill(
                Color.white.opacity(isSelected ? 0.06 : 0.03)
            )
            .shadow(
                color: isSelected
                    ? theme.palette.success.opacity(0.28)
                    : Color.black.opacity(0.28),
                radius: isSelected ? 18 : 12,
                x: 0,
                y: isSelected ? 8 : 6
            )
            .shadow(
                color: isSelected ? theme.palette.success.opacity(0.18) : .clear,
                radius: 26,
                x: 0,
                y: 0
            )
    }

    private func profileCardBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: profileCardCornerRadius, style: .continuous)
            .stroke(
                isSelected ? theme.palette.success.opacity(0.95) : Color.white.opacity(0.14),
                lineWidth: isSelected ? 2.5 : 1
            )
    }

    @ViewBuilder
    private func profileStatusBadge(isSelected: Bool, isProtected: Bool) -> some View {
        if isProtected {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.45))
                )
                .overlay(
                    Circle()
                        .stroke(theme.palette.success.opacity(0.55), lineWidth: 1)
                )
                .padding(8)
        } else if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(theme.palette.success)
                )
                .shadow(color: theme.palette.success.opacity(0.35), radius: 8, x: 0, y: 4)
                .padding(8)
        }
    }

    private func profileSubtitle(for user: PlexHomeUser) -> String {
        user.username ?? user.email ?? ""
    }

    private var placeholderAvatar: some View {
        LinearGradient(
            colors: [theme.palette.primary.opacity(0.8), theme.palette.primary.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(24)
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
            .buttonStyle(PlinxPrimaryActionButtonStyle())
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
