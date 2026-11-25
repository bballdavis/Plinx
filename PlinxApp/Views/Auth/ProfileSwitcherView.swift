#if !os(tvOS)
import PlinxUI
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx profile picker (iPhone and iPad)
//
// The one `ProfileSwitcherView` on iOS: launch profile selection, the Settings
// profile switcher, and the Plex Home step of account setup. It drives the
// absorbed `ProfileSwitcherViewModel` (local profiles, Plex Home users, PINs)
// with the Plinx quiet-shell design. The tvOS picker lives in
// `ProfileSwitcherView+tvOS.swift`.
//
// Parental rules (picker reachable by a child at launch):
//   • Continuing as the profile that was last active needs no gate. When no
//     profile is remembered as last active, every choice needs the gate.
//   • Switching to any other profile, managing profiles, adding a connection
//     and logging out are grown-up actions: they run behind the parental gate
//     unless a parent already unlocked protected UI (opened from Settings),
//     and the gate relocks once the action has run. The gate, not whether the
//     active Plex profile is restricted, decides who may manage profiles.
//   • The profile-management sheet shows the parental gate in place of its
//     content whenever the gate is locked, as Settings does, so it never
//     outlives the relock when the app leaves the foreground.
//   • Log Out is `PlinxSignOut.signOut`, the same full sign-out as Settings.
//   • Choosing the Plex Home user while adding an account is part of account
//     setup, which is already a grown-up flow.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
struct ProfileSwitcherView: View {
    private enum ManagementSheet: Identifiable {
        case profiles
        case connection(LocalProfile)

        var id: String {
            switch self {
            case .profiles:
                "profiles"
            case let .connection(profile):
                "connection.\(profile.id)"
            }
        }
    }

    @Environment(SessionManager.self) private var sessionManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ParentalAccessCoordinator.self) private var parentalAccess
    @Environment(\.plinxTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptChoice: ProfileChoice?
    @State private var pinInput = ""
    @FocusState private var isPinFieldFocused: Bool
    @State private var parentalRequest: PlinxParentalRequest?
    @State private var managementSheet: ManagementSheet?
    @State private var relocksAfterManagement = false
    @State private var isShowingLogoutConfirmation = false
    @State private var isSigningOut = false

    private let profileCardCornerRadius: CGFloat = 24
    private let onClose: (() -> Void)?

    /// - Parameter onClose: set when presented from protected Settings; shows a close control.
    init(viewModel: ProfileSwitcherViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    private var isExpanded: Bool {
        horizontalSizeClass == .regular
    }

    private var avatarSize: CGFloat { isExpanded ? 104 : 80 }
    /// Every tile shares one height, whether or not a username is shown.
    private var profileCardHeight: CGFloat { isExpanded ? 216 : 182 }

    private var isChoosingHomeUser: Bool {
        if case .chooseHomeUser = viewModel.mode {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .hero)

            GeometryReader { proxy in
                let layout = PlinxOnboardingLayout(width: proxy.size.width, height: proxy.size.height)
                let arrangement = layout.usesColumns
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                ScrollView {
                    arrangement {
                        header
                            .frame(maxWidth: layout.usesColumns ? 280 : .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            if let error = viewModel.errorMessage, pinPromptChoice == nil {
                                errorCard(error)
                                    .padding(.top, 20)
                            }
                            profilesGrid
                                .padding(.top, layout.usesColumns ? 0 : (isExpanded ? 36 : 28))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, isExpanded ? 24 : 16)
                    .padding(.bottom, 32)
                    .frame(maxWidth: layout.usesColumns ? 1180 : 960)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle(Text("auth.profile.header.title"))
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            chromeHeader
        }
        .disabled(isSigningOut)
        .alert(Text("common.actions.logOut", tableName: "Plinx"), isPresented: $isShowingLogoutConfirmation) {
            Button(role: .destructive) {
                isSigningOut = true
                Task {
                    // The one full sign-out: also revokes offline download
                    // access, the offline cache and the parental unlock.
                    await PlinxSignOut.signOut(
                        sessionManager: sessionManager,
                        downloadManager: downloadManager,
                        parentalAccess: parentalAccess
                    )
                    isSigningOut = false
                }
            } label: {
                Text("common.actions.logOut", tableName: "Plinx")
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text(Self.logoutMessage)
        }
        .task { await viewModel.load() }
        .plinxRefreshable { await viewModel.load() }
        .sheet(item: $pinPromptChoice, onDismiss: resetPinPrompt) { choice in
            pinPromptContent(for: choice)
                .presentationDetents([.medium, .large])
                .presentationBackground(theme.palette.background)
        }
        .sheet(item: $managementSheet, onDismiss: managementDidClose) { sheet in
            // Re-gated like Settings: the gate relocks when the app leaves the
            // foreground, and profile management must not outlive it.
            Group {
                if parentalAccess.isUnlocked {
                    NavigationStack {
                        switch sheet {
                        case .profiles:
                            ProfilesSettingsView()
                        case let .connection(profile):
                            ProfileDetailView(profileID: profile.id, startsWithNewConnection: true)
                        }
                    }
                } else {
                    ParentalGateView(onAllowed: {})
                }
            }
        }
        .plinxParentalApproval($parentalRequest)
        .onChange(of: viewModel.profileNeedingConnection) { _, profile in
            guard let profile else { return }
            viewModel.profileNeedingConnection = nil
            presentManagement(.connection(profile))
        }
        .onChange(of: pinInput) { _, newValue in
            let sanitized = String(newValue.filter(\.isNumber).prefix(4))
            if sanitized != newValue {
                pinInput = sanitized
            }
        }
        .accessibilityIdentifier("profileSwitcher")
    }

    // MARK: - Chrome

    /// Plinx chrome in place of the system navigation bar.
    private var chromeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if isChoosingHomeUser {
                PlinxOnboardingBackButton()
            } else {
                logoutChromeButton
            }
            Spacer(minLength: 0)
            if isChoosingHomeUser {
                PlinxOnboardingStepIndicator(step: .profile, isExpanded: isExpanded)
            } else {
                HStack(spacing: 12) {
                    if PlinxProfileSwitchRules.showsManageProfiles(mode: viewModel.mode) {
                        PlinxChromeButton(systemImage: "person.2.badge.gearshape") {
                            presentManagement(.profiles)
                        }
                        .accessibilityLabel(Text("profiles.manage"))
                        .accessibilityIdentifier("profileSwitcher.manage")
                    }
                    if let onClose {
                        PlinxChromeButton(systemImage: "xmark", action: onClose)
                            .accessibilityLabel(Text("common.actions.close", tableName: "Plinx"))
                            .accessibilityIdentifier("profileSwitcher.close")
                    } else if viewModel.canCancel {
                        PlinxChromeButton(systemImage: "xmark") {
                            viewModel.cancel()
                        }
                        .accessibilityLabel(Text("common.actions.cancel", tableName: "Plinx"))
                        .accessibilityIdentifier("profileSwitcher.cancel")
                    }
                }
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
            parentalAccess.requireParent($parentalRequest) {
                isShowingLogoutConfirmation = true
            }
        }
        .accessibilityIdentifier("profileSwitcher.logout")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("auth.profile.header.title")
                .font(.system(size: isExpanded ? 52 : 36, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Text(isChoosingHomeUser ? Self.homeUserSubtitle : Self.pickerSubtitle)
                .font(.system(isExpanded ? .title3 : .body, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.brandSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Profiles

    private var profilesGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: isExpanded ? 190 : 140), spacing: isExpanded ? 18 : 14)],
            spacing: isExpanded ? 18 : 14
        ) {
            if viewModel.choices.isEmpty {
                loadingState
            }
            ForEach(viewModel.choices) { choice in
                profileCard(for: choice)
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

    private func profileCard(for choice: ProfileChoice) -> some View {
        let isSelected = choice.isActive
        let subtitle = choice.detail ?? ""

        return Button {
            choose(choice)
        } label: {
            VStack(spacing: 12) {
                avatarView(for: choice)
                    .frame(width: avatarSize, height: avatarSize)

                VStack(spacing: 3) {
                    Text(choice.name)
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
                profileStatusBadge(isSelected: isSelected, isProtected: choice.requiresPIN)
            }
            .contentShape(RoundedRectangle(cornerRadius: profileCardCornerRadius, style: .continuous))
            .animation(theme.springs.interactive, value: isSelected)
        }
        .buttonStyle(PlinkButtonStyle(springs: theme.springs))
        .disabled(viewModel.switchingID != nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(
            choice.requiresPIN ? Text("auth.profile.pin.title") : Text(verbatim: "")
        )
        .accessibilityIdentifier("profileSwitcher.profile.\(choice.id)")
    }

    private func avatarView(for choice: ProfileChoice) -> some View {
        ZStack {
            if let url = choice.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderAvatar(for: choice)
                }
            } else {
                placeholderAvatar(for: choice)
            }
        }
        .clipShape(Circle())
        .overlay {
            if viewModel.switchingID == choice.id || viewModel.enteringID == choice.id {
                Circle()
                    .fill(Color.black.opacity(0.35))
                ProgressView().tint(Color.accentColor)
            }
        }
    }

    private func placeholderAvatar(for choice: ProfileChoice) -> some View {
        LinearGradient(
            colors: [choice.tint.opacity(0.95), choice.tint.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Text(verbatim: choice.initials)
                .font(.system(size: avatarSize * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(PlinxBrand.shell.opacity(0.85))
        )
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

    // MARK: - PIN

    private func pinPromptContent(for choice: ProfileChoice) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("auth.profile.pin.title")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("auth.profile.pin.prompt \(choice.name)")
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                PlinxChromeButton(systemImage: "xmark") {
                    resetPinPrompt()
                }
            }

            SecureField("auth.profile.pin.placeholder", text: $pinInput)
                .keyboardType(.numberPad)
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
                .accessibilityIdentifier("profileSwitcher.pin.field")

            Button {
                let enteredPin = pinInput
                resetPinPrompt()
                Task { await viewModel.select(choice, pin: enteredPin) }
            } label: {
                Text("common.actions.switchProfile")
            }
            .buttonStyle(PlinxActionButtonStyle())
            .disabled(pinInput.count < 4)
            .accessibilityIdentifier("profileSwitcher.pin.submit")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PlinxPageHeaderMetrics.horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.palette.background.ignoresSafeArea())
        .tint(.accentColor)
        .accessibilityElement(children: .contain)
        .onAppear { isPinFieldFocused = true }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .foregroundStyle(.white)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("common.actions.retry")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(theme.palette.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityIdentifier("profileSwitcher.retry")
        }
        .padding()
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func choose(_ choice: ProfileChoice) {
        guard viewModel.switchingID == nil, !isSigningOut else { return }
        if PlinxProfileSwitchRules.requiresParentalApproval(
            choosing: choice,
            mode: viewModel.mode,
            sessionManager: sessionManager
        ) {
            parentalAccess.requireParent($parentalRequest) {
                begin(choice)
            }
        } else {
            begin(choice)
        }
    }

    private func begin(_ choice: ProfileChoice) {
        viewModel.highlightedID = choice.id
        viewModel.errorMessage = nil
        if choice.requiresPIN {
            pinInput = ""
            pinPromptChoice = choice
        } else {
            Task { await viewModel.select(choice, pin: nil) }
        }
    }

    private func presentManagement(_ sheet: ManagementSheet) {
        let wasUnlocked = parentalAccess.isUnlocked
        parentalAccess.requireParent($parentalRequest, relocksAfterAction: false) {
            relocksAfterManagement = !wasUnlocked
            managementSheet = sheet
        }
    }

    private func managementDidClose() {
        viewModel.refreshChoices()
        if relocksAfterManagement {
            relocksAfterManagement = false
            parentalAccess.lock()
        }
    }

    private func resetPinPrompt() {
        pinPromptChoice = nil
        pinInput = ""
        isPinFieldFocused = false
    }
}
#endif

// MARK: - Shared rules and copy

/// Plinx's parental rules for the profile picker, shared by iOS and tvOS.
@MainActor
enum PlinxProfileSwitchRules {
    /// Continuing as the profile that was last active (or picking one during
    /// account setup) needs no gate; switching to anyone else is a grown-up
    /// action.
    static func requiresParentalApproval(
        choosing choice: ProfileChoice,
        mode: ProfileSwitcherViewModel.Mode,
        sessionManager: SessionManager
    ) -> Bool {
        requiresParentalApproval(
            choosingProfileID: choice.id,
            mode: mode,
            lastActiveProfileID: sessionManager.activeProfile?.id ?? sessionManager.profileStore.activeProfileID
        )
    }

    /// Fails closed: when no profile is remembered as last active (a removed
    /// Plex Home user, a deleted profile or account), no choice counts as
    /// continuing, so every choice needs the gate. Choosing the Plex Home user
    /// during account setup is the only exemption; the first launch remembers
    /// its profile before the picker can appear.
    static func requiresParentalApproval(
        choosingProfileID: String,
        mode: ProfileSwitcherViewModel.Mode,
        lastActiveProfileID: String?
    ) -> Bool {
        guard case .activateProfile = mode else { return false }
        guard let lastActiveProfileID else { return true }
        return choosingProfileID != lastActiveProfileID
    }

    /// "Manage profiles" is offered whenever the picker lists the family's
    /// profiles, and opens behind the parental gate, as Settings does.
    /// Upstream also hides it from a restricted Plex profile; in Plinx the gate
    /// is the stronger check, so who is signed in does not decide.
    static func showsManageProfiles(mode: ProfileSwitcherViewModel.Mode) -> Bool {
        if case .activateProfile = mode {
            return true
        }
        return false
    }
}

extension ProfileSwitcherView {
    static var pickerSubtitle: String {
        String(
            localized: "auth.profile.plinx.subtitle",
            defaultValue: "Keep watching as yourself. Switching to another profile needs a grown-up.",
            table: "Plinx"
        )
    }

    static var homeUserSubtitle: String {
        String(
            localized: "auth.profile.plinx.homeUserSubtitle",
            defaultValue: "Choose the Plex profile Plinx should use. Protected profiles ask for their PIN.",
            table: "Plinx"
        )
    }

    static var logoutMessage: String {
        String(
            localized: "auth.signOut.plinx.message",
            defaultValue: "Plinx will remove every Plex account and Jellyfin server from this device. Downloaded videos stay on the device.",
            table: "Plinx"
        )
    }
}
