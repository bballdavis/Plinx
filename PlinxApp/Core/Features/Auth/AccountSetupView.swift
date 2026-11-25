import PlinxUI
import SwiftUI

/// Hosts `AccountSetupFlow`: provider choice, sign-in, Plex Home user, server choice and, at first launch, the
/// optional "add another account" step. Every step uses the Plinx onboarding screens (`ProviderSelectionView`,
/// `SignInView`, `ProfileSwitcherView`, `SelectServerView`); Jellyfin sign-in uses `JellyfinAuthenticationView`.
struct AccountSetupView: View {
    @State private var flow: AccountSetupFlow
    private let onFinished: () -> Void

    init(purpose: AccountSetupFlow.Purpose, sessionManager: SessionManager, onFinished: @escaping () -> Void = {}) {
        _flow = State(initialValue: AccountSetupFlow(purpose: purpose, sessionManager: sessionManager))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack(path: $flow.path) {
            ProviderSelectionView(
                onSelect: flow.choose,
                offersSampleLibrary: flow.purpose == .firstLaunch && !flow.canFinishFromProviderChoice,
                onCancel: flow.purpose == .firstLaunch ? nil : { flow.cancel() }
            )
            .safeAreaInset(edge: .bottom) {
                if flow.canFinishFromProviderChoice {
                    PlinxOnboardingActionButton {
                        Task { await flow.finish() }
                    } label: {
                        Text("common.actions.continue")
                    }
                    .frame(maxWidth: 460)
                    .padding()
                    .accessibilityIdentifier("accountSetup.finish")
                }
            }
            .navigationDestination(for: AccountSetupFlow.Step.self, destination: destination)
        }
        .onChange(of: flow.isFinished) { _, isFinished in
            if isFinished {
                onFinished()
            }
        }
        .onDisappear {
            if !flow.isFinished, flow.purpose != .firstLaunch {
                flow.cancel()
            }
        }
    }

    @ViewBuilder
    private func destination(_ step: AccountSetupFlow.Step) -> some View {
        switch step {
        case .plexSignIn:
            SignInView(viewModel: SignInViewModel(onToken: { token in
                try await flow.plexSignedIn(token: token)
            }))
        case .jellyfin:
            JellyfinAuthenticationView(viewModel: JellyfinAuthenticationViewModel { session, connection in
                try flow.jellyfinSignedIn(session: session, connection: connection)
            })
        case let .plexHomeUser(accountID):
            ProfileSwitcherView(viewModel: ProfileSwitcherViewModel(
                sessionManager: flow.sessionManager,
                mode: .chooseHomeUser(accountID: accountID) { uuid, token in
                    await flow.plexHomeUserChosen(accountID: accountID, userUUID: uuid, token: token)
                },
            ))
        case let .plexServers(accountID, userUUID):
            SelectServerView(viewModel: ServerSelectionViewModel(
                loadServers: { try await flow.sessionManager.plexServers(accountID: accountID, userUUID: userUUID) },
                onContinue: { disabled in
                    flow.plexServersChosen(accountID: accountID, userUUID: userUUID, disabledServerIDs: disabled)
                },
            ))
        case .addAnotherAccount:
            AddAnotherAccountView(
                onAddAccount: flow.addAnotherAccount,
                onContinue: { Task { await flow.finish() } },
            )
        }
    }
}

/// Optional last step of the first launch, on the Plinx quiet shell.
struct AddAnotherAccountView: View {
    let onAddAccount: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .hero)

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("onboarding.addAnother.title")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(Self.subtitle)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                PlinxOnboardingActionButton(action: onContinue) {
                    Text("common.actions.continue")
                }
                .frame(maxWidth: 420)
                .accessibilityIdentifier("accountSetup.addAnother.continue")
                PlinxOnboardingActionButton(treatment: .secondary, action: onAddAccount) {
                    Text(Self.addButtonTitle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                .accessibilityIdentifier("accountSetup.addAnother.add")
                Spacer()
            }
            .padding(32)
        }
        #if !os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationBarBackButtonHidden()
    }

    static var subtitle: String {
        String(
            localized: "onboarding.addAnother.plinx.subtitle",
            defaultValue: "Plinx can show several Plex accounts and Jellyfin servers together, filtered by the same parental controls. You can also do this later in Settings.",
            table: "Plinx"
        )
    }

    static var addButtonTitle: String {
        String(
            localized: "onboarding.addAnother.plinx.button",
            defaultValue: "Add a Plex account or Jellyfin server",
            table: "Plinx"
        )
    }
}
