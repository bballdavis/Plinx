#if os(tvOS)
import SwiftUI
import PlinxUI

@MainActor
struct PlinxProfileSwitcherTVView: View {
    private enum PinFocusTarget: Hashable {
        case digit(String)
        case delete
        case cancel
    }

    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.plinxTheme) private var theme
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: PlexHomeUser?
    @State private var pinInput = ""
    @State private var isShowingLogoutConfirmation = false
    @FocusState private var focusedProfileID: String?
    @FocusState private var isLogoutFocused: Bool
    @FocusState private var pinFocusTarget: PinFocusTarget?
    private let loadsUsersOnAppear: Bool

    private let profileColumns = [
        GridItem(.adaptive(minimum: 270, maximum: 330), spacing: 36)
    ]

    init(
        viewModel: ProfileSwitcherViewModel,
        loadsUsersOnAppear: Bool = true
    ) {
        _viewModel = State(initialValue: viewModel)
        self.loadsUsersOnAppear = loadsUsersOnAppear
    }

    var body: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .restrained)

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
        .task {
            if loadsUsersOnAppear {
                await viewModel.loadUsers()
            }
            await Task.yield()
            restoreInitialProfileFocus()
        }
        .onChange(of: viewModel.users) { _, _ in
            restoreInitialProfileFocus()
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .fullScreenCover(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            pinEntrySheet(for: user)
        }
        .onChange(of: pinInput) { _, newValue in
            let sanitized = String(newValue.filter(\.isNumber).prefix(4))
            if sanitized != pinInput {
                pinInput = sanitized
                return
            }
            submitPinIfComplete()
        }
        .accessibilityIdentifier("profileSwitcher.tv")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("auth.profile.title")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("auth.profile.header.subtitle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 20)

            Button {
                isShowingLogoutConfirmation = true
            } label: {
                Label("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right")
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
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: profileColumns, alignment: .leading, spacing: 36) {
            if viewModel.users.isEmpty {
                loadingState
            }

            ForEach(viewModel.users) { user in
                profileButton(for: user)
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

    private func profileButton(for user: PlexHomeUser) -> some View {
        let isSelected = viewModel.activeUserUUID == user.uuid
        let isFocused = focusedProfileID == user.uuid

        return Button {
            if requiresPin(for: user) {
                pinInput = ""
                pinPromptUser = user
            } else {
                Task { await viewModel.switchToUser(user, pin: nil) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                avatar(for: user)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(user.friendlyName ?? user.title ?? "?")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(user.username ?? user.email ?? "")
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
        .focused($focusedProfileID, equals: user.uuid)
        .onMoveCommand { direction in
            guard direction == .up else { return }
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
        .accessibilityIdentifier("profileSwitcher.profile.\(user.uuid)")
        .accessibilityValue(
            isSelected ? "activeProfilePlinxSurface" : "profilePlinxSurface"
        )
    }

    private func avatar(for user: PlexHomeUser) -> some View {
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

            if viewModel.switchingUserUUID == user.uuid {
                Color.black.opacity(0.45)
                ProgressView().tint(theme.palette.primary)
            }

            VStack {
                HStack {
                    Spacer()
                    if requiresPin(for: user) {
                        profileBadge(systemImage: "lock.fill", fill: Color.black.opacity(0.58))
                    } else if viewModel.activeUserUUID == user.uuid {
                        profileBadge(systemImage: "checkmark", fill: theme.palette.success)
                    }
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private var placeholderAvatar: some View {
        LinearGradient(
            colors: [theme.palette.primary.opacity(0.88), theme.palette.accent.opacity(0.58)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(48)
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
                Task { await viewModel.loadUsers() }
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

    private func pinEntrySheet(for user: PlexHomeUser) -> some View {
        ZStack {
            PlinxAmbientBackground(intensity: .restrained)

            VStack(alignment: .center, spacing: 18) {
                Text("auth.profile.pin.title")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                let displayName = user.friendlyName ?? user.title ?? "?"
                Text("auth.profile.pin.prompt \(displayName)")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))

                pinDisplay
                keypad

                Button {
                    resetPinPrompt()
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
        }
        .onAppear { pinFocusTarget = .digit("1") }
        .onExitCommand(perform: resetPinPrompt)
        .accessibilityIdentifier("profileSwitcher.pin.sheet")
    }

    private var pinDisplay: some View {
        HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(PlinxBrand.surface)
                    .frame(width: 82, height: 64)
                    .overlay {
                        Text(index < pinInput.count ? "•" : "")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("auth.profile.pin.title")
        .accessibilityValue(pinInput.isEmpty ? "Empty" : String(repeating: "•", count: pinInput.count))
        .accessibilityIdentifier("profileSwitcher.pin.display")
    }

    private let keypadColumns = [
        GridItem(.fixed(128), spacing: 12),
        GridItem(.fixed(128), spacing: 12),
        GridItem(.fixed(128), spacing: 12)
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
            guard pinInput.count < 4 else { return }
            pinInput.append(digit)
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
        .accessibilityIdentifier("profileSwitcher.pin.key.\(digit)")
    }

    private var keypadDeleteButton: some View {
        Button {
            guard !pinInput.isEmpty else { return }
            pinInput.removeLast()
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
        .disabled(pinInput.isEmpty)
        .accessibilityIdentifier("profileSwitcher.pin.delete")
    }

    private var preferredProfileID: String? {
        guard !viewModel.users.isEmpty else { return nil }
        if let active = viewModel.activeUserUUID,
           viewModel.users.contains(where: { $0.uuid == active }) {
            return active
        }
        return viewModel.users.first?.uuid
    }

    private func restoreInitialProfileFocus() {
        guard focusedProfileID == nil, !isLogoutFocused else { return }
        focusedProfileID = preferredProfileID
    }

    private func requiresPin(for user: PlexHomeUser) -> Bool {
        user.protected ?? false
    }

    private func resetPinPrompt() {
        pinPromptUser = nil
        pinInput = ""
        pinFocusTarget = nil
    }

    private func submitPinIfComplete() {
        guard pinInput.count == 4, let user = pinPromptUser else { return }
        let enteredPin = pinInput
        Task { await viewModel.switchToUser(user, pin: enteredPin) }
        resetPinPrompt()
    }
}
#endif
