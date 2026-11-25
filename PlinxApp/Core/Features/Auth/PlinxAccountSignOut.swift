import Foundation

extension SessionManager {
    /// Plinx "Log Out": removes every Plex account and Jellyfin server (with
    /// their tokens, profile links and server choices), stops the sample
    /// library, and returns to onboarding. Downloads stay on the device, still
    /// scoped to the profile that created them. Callers present this only
    /// behind the parental gate.
    func signOutAllAccounts() async {
        if DemoFixtureBootstrap.isActive {
            DemoFixtureBootstrap.stop()
        }
        // Jellyfin first: with no Jellyfin account left, removing the last Plex
        // account cannot create and activate a fallback profile mid-sign-out.
        let ordered = accounts.filter { $0.provider == .jellyfin } + accounts.filter { $0.provider != .jellyfin }
        for account in ordered {
            removeAccount(account.id)
        }
        // Removing accounts while no profile is active leaves the status as it
        // was; a fresh hydration lands on account setup.
        if accounts.isEmpty, status != .needsAccount {
            await hydrate()
        }
    }
}
