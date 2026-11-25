import Foundation

/// UI-test-only sign-in from the launch environment (`--ui-testing`, `PLINX_UI_TEST_MODE=live`, `PLINX_PLEX_TOKEN`).
/// Debug builds only: in Release both launch hooks do nothing, so no launch argument or environment value can sign a
/// shipped app in.
///
/// - With `PLINX_PLEX_SERVER_URL`, the session is that server alone, reached directly (`PlexDirectSession`): no
///   plex.tv round trip, so local fixture servers with a placeholder token work as well as a real server.
/// - Without it, the token is primed where an upgrading install keeps it, so `MultiServerMigration` adopts it as the
///   family's Plex account at hydration. On a simulator that already migrated, the token is added as a new Plex
///   account and its owner's profile is activated, as a first-launch sign-in would.
@MainActor
enum LivePlexUITestBootstrap {
    /// Call before the `SessionManager` exists. Only a plex.tv sign-in is primed; a direct server session is created
    /// in `bootstrapIfNeeded` and needs no stored credential.
    static func primeCredentialsIfNeeded(environment: [String: String]) {
        #if DEBUG
            guard isActive(environment: environment),
                  let token = token(in: environment),
                  serverURL(in: environment) == nil,
                  let bundleIdentifier = Bundle.main.bundleIdentifier
            else { return }

            do {
                try Keychain(service: bundleIdentifier)
                    .setString(token, forKey: MultiServerMigration.LegacyKeys.plexToken)
            } catch {
                print("LivePlexUITestBootstrap failed to seed token: \(error)")
            }
        #endif
    }

    /// Call right after the `SessionManager` is created, before its hydration task runs.
    static func bootstrapIfNeeded(
        environment: [String: String],
        sessionManager: SessionManager
    ) {
        #if DEBUG
            guard isActive(environment: environment), let token = token(in: environment) else { return }

            let directSession = serverURL(in: environment).flatMap { url in
                PlexDirectSession(
                    userUUID: userUUID,
                    displayName: profileName,
                    token: token,
                    serverName: serverName,
                    serverIdentifier: serverIdentifier,
                    serverURL: url
                )
            }
            if let directSession {
                // Before hydration: the stored account then carries this launch's token and address, and its
                // plex.tv requests are answered on the device from the start.
                directSession.store(in: sessionManager)
            }

            Task { @MainActor in
                await waitForHydration(of: sessionManager)
                if let directSession {
                    if !(await directSession.activate(on: sessionManager)) {
                        print("LivePlexUITestBootstrap: \(directSession.resource.name) did not answer")
                    }
                } else {
                    await signIn(token: token, sessionManager: sessionManager)
                }
            }
        #endif
    }
}

#if DEBUG
    extension LivePlexUITestBootstrap {
        static let mode = "live"
        static let serverIdentifier = "plinx-live-ui-test"
        /// Plex user of the direct session's account.
        static let userUUID = "plinx-live-ui-test-user"
        private static let serverName = "Plinx Live UI Test"
        private static let profileName = "Live UI Test"

        static func isActive(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Bool {
            arguments.contains("--ui-testing") && environment["PLINX_UI_TEST_MODE"] == mode
        }

        // MARK: - plex.tv sign-in

        private static func signIn(token: String, sessionManager: SessionManager) async {
            switch sessionManager.status {
            case .needsAccount, .migrationFailed:
                do {
                    let addition = try await sessionManager.addPlexAccount(token: token)
                    sessionManager.profileStore.setActiveProfile(PlexHomeProfile.id(userUUID: addition.ownerUUID))
                    await sessionManager.finishFirstLaunch()
                } catch {
                    print("LivePlexUITestBootstrap failed to sign in: \(error)")
                }
            case .needsProfileSelection:
                if let profile = ownerProfile(of: token, in: sessionManager) {
                    await sessionManager.activate(profile)
                }
            case .hydrating, .ready:
                break
            }
        }

        /// Profile of the Plex user owning `token`, when that account is already stored.
        private static func ownerProfile(of token: String, in sessionManager: SessionManager) -> StrimrProfile? {
            let accountStore = sessionManager.accountStore
            guard let account = accountStore.plexAccounts.first(where: { account in
                (try? accountStore.token(for: .plex(account))) == token
            }) else { return nil }
            let profileID = PlexHomeProfile.id(userUUID: account.id)
            return sessionManager.profiles.first { $0.id == profileID }
        }

        private static func waitForHydration(of sessionManager: SessionManager) async {
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while sessionManager.status == .hydrating, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // MARK: - Environment

        private static func token(in environment: [String: String]) -> String? {
            validated(environment["PLINX_PLEX_TOKEN"])
        }

        private static func serverURL(in environment: [String: String]) -> URL? {
            guard let value = validated(environment["PLINX_PLEX_SERVER_URL"]),
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  url.host?.isEmpty == false
            else { return nil }
            return url
        }

        /// Unresolved scheme macros such as `$(PLINX_PLEX_TOKEN)` count as missing.
        private static func validated(_ rawValue: String?) -> String? {
            guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !value.contains("$(")
            else { return nil }
            return value
        }
    }
#endif
