#if os(tvOS)
import PlinxUI
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx profile picker (Apple TV)
//
// The one `ProfileSwitcherView` on tvOS (formerly `PlinxProfileSwitcherTVView`;
// upstream's tvOS picker is not compiled). Dark Plinx surfaces, the shared
// focus ring, and a remote-friendly PIN keypad driven by the absorbed
// `ProfileSwitcherViewModel`. Parental rules: see `PlinxProfileSwitchRules`
// and the iOS picker.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
struct ProfileSwitcherView: View {
    private enum PinFocusTarget: Hashable {
        case digit(String)
        case delete
        case cancel
    }

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
    @Environment(ParentalAccessCoordinator.self) private var parentalAccess
    @Environment(\.plinxTheme) private var theme
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var parentalRequest: PlinxParentalRequest?
    @State private var managementSheet: ManagementSheet?
    @State private var relocksAfterManagement = false
    @State private var isShowingLogoutConfirmation = false
    @State private var isSigningOut = false
    @FocusState private var focusedProfileID: String?
    @FocusState private var isLogoutFocused: Bool
    @FocusState private var pinFocusTarget: PinFocusTarget?
    @Namespace private var profileFocusNamespace
    private let loadsProfilesOnAppear: Bool
    private let onClose: (() -> Void)?

    private let profileColumns = [
        GridItem(.adaptive(minimum: 270, maximum: 330), spacing: 36),
    ]

    /// - Parameters:
    ///   - loadsProfilesOnAppear: `false` keeps fixture choices set by UI-test harnesses.
    ///   - onClose: set when presented from protected Settings.
    init(
        viewModel: ProfileSwitcherViewModel,
        loadsProfilesOnAppear: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.loadsProfilesOnAppear = loadsProfilesOnAppear
        self.onClose = onClose
    }

    private var isChoosingHomeUser: Bool {
        if case .chooseHomeUser = viewModel.mode {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .restrained)

            if let pinChoice = viewModel.pinChoice {
                pinStage(for: pinChoice)
                    .transition(.opacity)
            } else {
                picker
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.pinChoice)
        .disabled(isSigningOut)
        .task {
            if loadsProfilesOnAppear {
                await viewModel.load()
            }
            await Task.yield()
            restoreInitialProfileFocus()
        }
        .onChange(of: viewModel.choices) { _, _ in
            restoreInitialProfileFocus()
        }
        .onChange(of: viewModel.pinChoice) { _, choice in
            if choice != nil {
                pinFocusTarget = .digit("1")
            } else {
                focusedProfileID = viewModel.highlightedID ?? preferredProfileID
            }
        }
        .onChange(of: viewModel.profileNeedingConnection) { _, profile in
            guard let profile else { return }
            viewModel.profileNeedingConnection = nil
            presentManagement(.connection(profile))
        }
        .alert(Text("common.actions.logOut", tableName: "Plinx"), isPresented: $isShowingLogoutConfirmation) {
            Button(role: .destructive) {
                isSigningOut = true
                Task {
                    // The one full sign-out, as in Settings.
                    await PlinxSignOut.signOut(sessionManager: sessionManager, parentalAccess: parentalAccess)
                    isSigningOut = false
                }
            } label: {
                Text("common.actions.logOut", tableName: "Plinx")
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text(Self.logoutMessage)
        }
        .taskPresentation(item: $managementSheet, style: .compactModal, onDismiss: managementDidClose) { sheet in
            switch sheet {
            case .profiles:
                NavigationStack { ProfilesSettingsView() }
            case let .connection(profile):
                TaskModalNavigationView {
                    ProfileDetailView(profileID: profile.id, startsWithNewConnection: true)
                }
            }
        }
        .plinxParentalApproval($parentalRequest)
        .accessibilityIdentifier("profileSwitcher.tv")
        .focusScope(profileFocusNamespace)
    }

    // MARK: - Picker

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header

                if let error = viewModel.errorMessage {
                    errorCard(error)
                }

                profilesGrid
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 48)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("auth.profile.header.title")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(isChoosingHomeUser ? Self.homeUserSubtitle : Self.pickerSubtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 20)

            // While adding an account, Menu returns to the previous setup step.
            HStack(spacing: 20) {
                if !isChoosingHomeUser {
                    if PlinxProfileSwitchRules.showsManageProfiles(mode: viewModel.mode) {
                        headerButton(
                            titleKey: "profiles.manage",
                            systemImage: "person.2.badge.gearshape",
                            identifier: "profileSwitcher.manage",
                            usesPlinxTable: false,
                            action: { presentManagement(.profiles) }
                        )
                    }
                    if let onClose {
                        headerButton(
                            titleKey: "common.actions.close",
                            systemImage: "xmark",
                            identifier: "profileSwitcher.close",
                            action: onClose
                        )
                    } else if viewModel.canCancel {
                        headerButton(
                            titleKey: "common.actions.cancel",
                            systemImage: "xmark",
                            identifier: "profileSwitcher.cancel",
                            action: { viewModel.cancel() }
                        )
                    }
                    logoutButton
                }
            }
            .focusSection()
        }
    }

    private func headerButton(
        titleKey: String,
        systemImage: String,
        identifier: String,
        usesPlinxTable: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                if usesPlinxTable {
                    Text(LocalizedStringKey(titleKey), tableName: "Plinx")
                } else {
                    Text(LocalizedStringKey(titleKey))
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.system(size: 25, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 24)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PlinxBrand.surface.opacity(0.98))
            )
        }
        .onMoveCommand { direction in
            guard direction == .down else { return }
            focusedProfileID = preferredProfileID
        }
        .plinxTVFocusButton(
            style: PlinxFocusSurfaceStyle(
                focusedScale: 1.025,
                cornerRadius: 20,
                focusedFillOpacity: 0.1
            )
        )
        .accessibilityIdentifier(identifier)
    }

    private var logoutButton: some View {
        Button {
            parentalAccess.requireParent($parentalRequest) {
                isShowingLogoutConfirmation = true
            }
        } label: {
            Label {
                Text("common.actions.logOut", tableName: "Plinx")
            } icon: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .font(.system(size: 25, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.red.opacity(0.9))
            .padding(.horizontal, 24)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PlinxBrand.surface.opacity(0.98))
            )
        }
        .focused($isLogoutFocused)
        .onMoveCommand { direction in
            guard direction == .down else { return }
            focusedProfileID = preferredProfileID
        }
        .plinxTVFocusButton(
            style: PlinxFocusSurfaceStyle(
                focusedScale: 1.025,
                cornerRadius: 20,
                focusedFillOpacity: 0.1
            )
        )
        .accessibilityIdentifier("profileSwitcher.logout")
        .accessibilityValue("darkPlinxDestructiveWithGradientFocus")
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: profileColumns, alignment: .leading, spacing: 36) {
            if viewModel.choices.isEmpty {
                loadingState
            }

            ForEach(viewModel.choices) { choice in
                profileButton(for: choice)
            }
        }
    }

    @ViewBuilder
    private var loadingState: some View {
        if viewModel.isLoading {
            PlinxBrandedLoadingView(
                context: .content,
                titleKey: LocalizedStringResource("auth.profile.loading")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if viewModel.errorMessage == nil {
            Text("auth.profile.empty")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func profileButton(for choice: ProfileChoice) -> some View {
        let isSelected = choice.isActive
        let isFocused = focusedProfileID == choice.id

        return Button {
            choose(choice)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                avatar(for: choice)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(choice.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(choice.detail ?? "")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .frame(height: 24, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        isFocused
                            ? PlinxBrand.surface.opacity(1)
                            : PlinxBrand.surface.opacity(isSelected ? 0.94 : 0.78)
                    )
            )
        }
        .focused($focusedProfileID, equals: choice.id)
        .prefersDefaultFocus(choice.id == preferredProfileID, in: profileFocusNamespace)
        .onMoveCommand { direction in
            guard direction == .up, !isChoosingHomeUser else { return }
            isLogoutFocused = true
        }
        .plinxTVFocusButton(
            isSelected: isSelected,
            style: PlinxFocusSurfaceStyle(
                selectionOpacity: 0.72,
                focusedScale: 1.025,
                focusedShadowRadius: 20,
                cornerRadius: 24,
                focusedFillOpacity: 0.08
            )
        )
        .disabled(viewModel.switchingID != nil)
        .accessibilityIdentifier("profileSwitcher.profile.\(choice.id)")
        .accessibilityValue(
            isSelected ? "activeProfilePlinxSurface" : "profilePlinxSurface"
        )
    }

    private func avatar(for choice: ProfileChoice) -> some View {
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

            if viewModel.switchingID == choice.id || viewModel.enteringID == choice.id {
                Color.black.opacity(0.45)
                ProgressView().tint(theme.palette.primary)
            }

            VStack {
                HStack {
                    Spacer()
                    if choice.requiresPIN {
                        profileBadge(systemImage: "lock.fill", fill: Color.black.opacity(0.58))
                    } else if choice.isActive {
                        profileBadge(systemImage: "checkmark", fill: theme.palette.success)
                    }
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private func placeholderAvatar(for choice: ProfileChoice) -> some View {
        LinearGradient(
            colors: [choice.tint.opacity(0.88), theme.palette.accent.opacity(0.58)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Text(verbatim: choice.initials)
                .font(.system(size: 88, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func profileBadge(systemImage: String, fill: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(fill))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 20) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Button {
                Task { await viewModel.load() }
            } label: {
                Label("common.actions.retry", systemImage: "arrow.clockwise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 66)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PlinxBrand.surface)
                    )
            }
            .plinxTVFocusButton(
                style: PlinxFocusSurfaceStyle(cornerRadius: 18, focusedFillOpacity: 0.1)
            )
            .accessibilityIdentifier("profileSwitcher.retry")
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PlinxBrand.surface.opacity(0.72))
        )
    }

    // MARK: - PIN keypad

    private func pinStage(for choice: ProfileChoice) -> some View {
        VStack(alignment: .center, spacing: 18) {
            Text("auth.profile.pin.title")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(viewModel.errorMessage ?? String(localized: "auth.profile.pin.prompt \(choice.name)"))
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))

            pinDisplay
            keypad

            Button {
                viewModel.cancelPIN()
            } label: {
                Text("common.actions.cancel")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 420, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PlinxBrand.surface)
                    )
            }
            .focused($pinFocusTarget, equals: .cancel)
            .plinxTVFocusButton(
                style: PlinxFocusSurfaceStyle(cornerRadius: 18, focusedFillOpacity: 0.08)
            )
            .accessibilityIdentifier("profileSwitcher.pin.cancel")
            .accessibilityValue("darkPlinxPINCancel")
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pinFocusTarget = .digit("1") }
        .onExitCommand(perform: viewModel.cancelPIN)
        .accessibilityIdentifier("profileSwitcher.pin.sheet")
    }

    private var pinDisplay: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(PlinxBrand.surface)
                    .frame(width: 82, height: 64)
                    .overlay {
                        Text(index < viewModel.pin.count ? "•" : "")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .modifier(PlinxPINShake(trigger: viewModel.rejectedPINCount))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("auth.profile.pin.title"))
        .accessibilityValue(viewModel.pin.isEmpty ? "Empty" : String(repeating: "•", count: viewModel.pin.count))
        .accessibilityIdentifier("profileSwitcher.pin.display")
    }

    private let keypadColumns = [
        GridItem(.fixed(128), spacing: 12),
        GridItem(.fixed(128), spacing: 12),
        GridItem(.fixed(128), spacing: 12),
    ]

    private var keypad: some View {
        LazyVGrid(columns: keypadColumns, spacing: 12) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) {
                keypadDigitButton($0)
            }

            Color.clear.frame(width: 128, height: 62)
            keypadDigitButton("0")
            keypadDeleteButton
        }
    }

    private func keypadDigitButton(_ digit: String) -> some View {
        Button {
            viewModel.appendPINDigit(digit)
        } label: {
            Text(digit)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 128, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PlinxBrand.surface)
                )
        }
        .focused($pinFocusTarget, equals: .digit(digit))
        .plinxTVFocusButton(
            style: PlinxFocusSurfaceStyle(cornerRadius: 18, focusedFillOpacity: 0.12)
        )
        .disabled(viewModel.switchingID != nil)
        .accessibilityIdentifier("profileSwitcher.pin.key.\(digit)")
    }

    private var keypadDeleteButton: some View {
        Button {
            viewModel.deletePINDigit()
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 128, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PlinxBrand.surface)
                )
        }
        .focused($pinFocusTarget, equals: .delete)
        .plinxTVFocusButton(
            style: PlinxFocusSurfaceStyle(cornerRadius: 18, focusedFillOpacity: 0.12)
        )
        .disabled(viewModel.pin.isEmpty)
        .accessibilityIdentifier("profileSwitcher.pin.delete")
    }

    // MARK: - Focus

    private var preferredProfileID: String? {
        guard !viewModel.choices.isEmpty else { return nil }
        return (viewModel.choices.first(where: \.isActive) ?? viewModel.choices.first)?.id
    }

    private func restoreInitialProfileFocus() {
        guard focusedProfileID == nil, !isLogoutFocused, viewModel.pinChoice == nil else { return }
        focusedProfileID = preferredProfileID
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
                viewModel.choose(choice)
            }
        } else {
            viewModel.choose(choice)
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
}

/// Short horizontal shake after a rejected PIN.
private struct PlinxPINShake: ViewModifier {
    let trigger: Int
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.12, dampingFraction: 0.2)) {
                    offset = 18
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.12)) {
                    offset = 0
                }
            }
    }
}
#endif
