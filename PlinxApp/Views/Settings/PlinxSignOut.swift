import Foundation

/// Plinx "Log Out": removes every Plex account and Jellyfin server and revokes
/// everything on the device that let it reach the family's media without
/// signing in again. Only reachable behind the parental gate.
///
/// Revoked:
/// - account tokens, profile links and server choices (`signOutAllAccounts`);
/// - the active download owners, so no download is listed or playable until a
///   profile signs in again (downloads stay on the device, still owned by the
///   profile that made them);
/// - the offline browsing cache of titles and artwork;
/// - the pre-multi-server offline session snapshot (`plinx.offlineSession.v1`),
///   which earlier builds used to authorize offline Downloads;
/// - on Apple TV, any Top Shelf credentials an earlier build shared;
/// - the parental unlock, so nothing protected stays open behind onboarding.
@MainActor
enum PlinxSignOut {
    /// Keychain item of the retired `PlinxSessionAccessCoordinator`.
    static let legacyOfflineSessionKey = "plinx.offlineSession.v1"

    #if os(tvOS)
    static func signOut(
        sessionManager: SessionManager,
        parentalAccess: ParentalAccessCoordinator
    ) async {
        await sessionManager.signOutAllAccounts()
        TopShelfSessionStore().clear()
        removeLegacyOfflineAuthorization()
        parentalAccess.lock()
    }
    #else
    static func signOut(
        sessionManager: SessionManager,
        downloadManager: DownloadManager,
        offlineCoordinator: OfflineCoordinator = .shared,
        parentalAccess: ParentalAccessCoordinator
    ) async {
        // Push watch progress recorded offline while the tokens still exist.
        // An unreachable server keeps its journal on the device, as account
        // removal does.
        let owners = Set(sessionManager.accounts.flatMap { sessionManager.owners(ofAccount: $0.id) })
        for owner in owners {
            _ = await offlineCoordinator.synchronizeProgressNow(owner: owner)
        }

        await sessionManager.signOutAllAccounts()

        // Fail closed at once rather than waiting for the shell to observe the
        // emptied registry.
        downloadManager.activateOwners([])
        offlineCoordinator.clearCache()
        removeLegacyOfflineAuthorization()
        parentalAccess.lock()
    }
    #endif

    static func removeLegacyOfflineAuthorization(
        keychain: Keychain = Keychain(service: Bundle.main.bundleIdentifier ?? "com.bballdavis.plinx")
    ) {
        // A failed delete leaves an item nothing reads any more.
        try? keychain.deleteValue(forKey: legacyOfflineSessionKey)
    }
}

/// Relocks the parental gate when unlocked Settings leaves the screen without
/// the shell's close path: switching profile, removing an account or Log Out
/// rebuild the root shell, which tears Settings down without closing it.
///
/// Held in `@State` and armed in `onAppear`, so the throwaway instances SwiftUI
/// creates while re-initializing the view never lock anything.
final class PlinxSettingsAccessLease {
    private var coordinator: ParentalAccessCoordinator?

    @MainActor
    func hold(_ coordinator: ParentalAccessCoordinator) {
        self.coordinator = coordinator
    }

    deinit {
        guard let coordinator else { return }
        Task { @MainActor in
            coordinator.lock()
        }
    }
}
