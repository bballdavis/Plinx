import PlinxUI
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Accounts and servers (parent-only)
//
// Replaces the single "Default Server" page: with multi-server sessions every
// account's servers are listed, each can be switched on or off for the active
// profile, and a parent can add a Plex account or a Jellyfin server through
// the Plinx-branded `AccountSetupView`. Every server goes through the same
// `SafeMediaServices` boundary, so adding one never widens what a child sees
// beyond the family's rating policy.
//
// iPhone and iPad use upstream `AccountsSettingsView` (its removal flow also
// asks whether the account's downloads are kept). Apple TV cannot host
// upstream's tvOS settings focus system, so it gets the same actions on the
// Plinx Settings list.
// ─────────────────────────────────────────────────────────────────────────────

#if !os(tvOS)
struct PlinxAccountsSettingsView: View {
    var body: some View {
        AccountsSettingsView()
            .navigationBarTitleDisplayMode(.large)
            .background(Color.appBackground.ignoresSafeArea())
            .plinxSettingsChrome()
            .accessibilityIdentifier("settings.accounts.screen")
    }
}
#else
struct PlinxAccountsSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isAddingAccount = false
    @State private var accountPendingRemoval: MediaAccount?
    @State private var reconnectingAccount: MediaAccount?

    var body: some View {
        List {
            ForEach(sessionManager.accounts) { account in
                Section {
                    accountContent(account)
                } header: {
                    Text(verbatim: "\(account.displayName) · \(providerName(account))")
                } footer: {
                    if sessionManager.isAccountUnused(account.id) {
                        Text("settings.accounts.unused")
                    }
                }
            }

            Section {
                Button {
                    isAddingAccount = true
                } label: {
                    Label("settings.accounts.add", systemImage: "plus.circle")
                }
                .plinxSettingsListButton()
                .accessibilityIdentifier("settings.accounts.add")
            }
        }
        .plinxSettingsListPage(title: Text("settings.accounts.title"))
        .accessibilityIdentifier("settings.accounts.screen")
        .taskPresentation(isPresented: $isAddingAccount, style: .fullScreen) {
            AccountSetupView(purpose: .settings, sessionManager: sessionManager) {
                isAddingAccount = false
            }
        }
        .taskPresentation(item: $reconnectingAccount, style: .fullScreen) { account in
            NavigationStack {
                ReconnectAccountView(account: account) { reconnectingAccount = nil }
            }
        }
        .alert(
            "settings.accounts.remove.title",
            isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        accountPendingRemoval = nil
                    }
                }
            ),
            presenting: accountPendingRemoval
        ) { account in
            Button("settings.accounts.remove", role: .destructive) {
                sessionManager.removeAccount(account.id)
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: { account in
            Text("settings.accounts.remove.message \(account.displayName)")
        }
    }

    @ViewBuilder
    private func accountContent(_ account: MediaAccount) -> some View {
        let sessions = sessionManager.registry.sessions(accountID: account.id)
        if sessions.isEmpty {
            Text(isLinkedToActiveProfile(account) ? "settings.accounts.noServers" : "settings.accounts.notLinked")
                .foregroundStyle(.secondary)
        }
        ForEach(sessions) { session in
            NavigationLink {
                ServerDetailView(server: session.identity)
                    .background(Color.appBackground.ignoresSafeArea())
                    .plinxSettingsChrome()
            } label: {
                HStack(spacing: 18) {
                    ServerSessionRow(session: session)
                    Spacer(minLength: 18)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .plinxSettingsListButton()
            .accessibilityIdentifier("settings.accounts.server.\(session.identity.stableKey)")

            if session.status == .needsReauthentication {
                Button("settings.accounts.reconnect") { reconnectingAccount = account }
                    .plinxSettingsListButton()
            }
        }
        if sessionManager.registry.linkStatuses[account.id] == .needsReauthentication, sessions.isEmpty {
            Button("settings.accounts.reconnect") { reconnectingAccount = account }
                .plinxSettingsListButton()
        }
        Button(role: .destructive) {
            accountPendingRemoval = account
        } label: {
            Text("settings.accounts.remove")
                .foregroundStyle(.red)
        }
        .plinxSettingsListButton()
    }

    private func providerName(_ account: MediaAccount) -> String {
        account.provider == .plex
            ? String(localized: "provider.plex")
            : String(localized: "provider.jellyfin")
    }

    private func isLinkedToActiveProfile(_ account: MediaAccount) -> Bool {
        guard let profile = sessionManager.activeProfile else { return false }
        return sessionManager.links(for: profile).contains { $0.accountID == account.id }
    }
}
#endif
