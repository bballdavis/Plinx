import Foundation

@MainActor
enum LivePlexUITestBootstrap {
    static let mode = "live"
    static let offlineReconnectScreenName = "liveOfflineReconnect"
    private static let tokenKey = "strimr.plex.authToken"

    static func isActive(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains("--ui-testing") && environment["PLINX_UI_TEST_MODE"] == mode
    }

    static func bootstrapIfNeeded(
        environment: [String: String],
        sessionManager: SessionManager,
        context: PlexAPIContext,
        downloadManager: DownloadManager
    ) {
        guard isActive(environment: environment) else { return }
        guard let token = environment["PLINX_PLEX_TOKEN"], !token.isEmpty else { return }

        Task { @MainActor in
            do {
                try await prepareLiveSession(
                    token: token,
                    serverRaw: environment["PLINX_PLEX_SERVER_URL"],
                    sessionManager: sessionManager,
                    context: context
                )

                if environment["PLINX_UI_TEST_SCREEN"] == offlineReconnectScreenName,
                   sessionManager.status == .ready {
                    downloadManager.markOfflineDueToConnectionFailure()
                }
            } catch {
                print("LivePlexUITestBootstrap failed: \(error)")
            }
        }
    }

    static func primeCredentialsIfNeeded(environment: [String: String]) {
        guard isActive(environment: environment) else { return }
        guard let token = environment["PLINX_PLEX_TOKEN"], !token.isEmpty else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        do {
            try Keychain(service: bundleIdentifier).setString(token, forKey: tokenKey)
        } catch {
            print("LivePlexUITestBootstrap failed to seed token: \(error)")
        }
    }

    private static func prepareLiveSession(
        token: String,
        serverRaw: String?,
        sessionManager: SessionManager,
        context: PlexAPIContext
    ) async throws {
        while sessionManager.status == .hydrating {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if let resource = makeDirectResource(serverRaw: serverRaw, token: token) {
            await sessionManager.bootstrapDirectServerSession(resource: resource, token: token)
            return
        }

        if sessionManager.status != .ready {
            await sessionManager.hydrate()
        }

        if sessionManager.status == .signedOut {
            try await sessionManager.signIn(with: token)
        }

        guard sessionManager.status == .needsServerSelection else { return }
        guard let resource = try await resolveResource(serverRaw: serverRaw, context: context) else { return }
        await sessionManager.selectServer(resource, setAsDefault: true)
    }

    private static func makeDirectResource(serverRaw: String?, token: String) -> PlexCloudResource? {
        guard let serverRaw,
              let serverURL = URL(string: serverRaw),
              let host = serverURL.host,
              let scheme = serverURL.scheme else {
            return nil
        }

        let connection = PlexCloudResource.Connection(
            scheme: scheme,
            address: host,
            port: serverURL.port ?? (scheme.lowercased() == "https" ? 443 : 80),
            uri: serverURL,
            isLocal: true,
            isRelay: false,
            isIPv6: host.contains(":" )
        )

        return PlexCloudResource(
            name: "Plinx Live UI Test",
            clientIdentifier: "plinx-live-ui-test",
            accessToken: token,
            connections: [connection]
        )
    }

    private static func resolveResource(
        serverRaw: String?,
        context: PlexAPIContext
    ) async throws -> PlexCloudResource? {
        let resources = try await ResourceRepository(context: context).getAvailableResources()

        guard let serverRaw,
              let serverURL = URL(string: serverRaw),
              let host = serverURL.host,
              let scheme = serverURL.scheme else {
            return resources.count == 1 ? resources.first : nil
        }

        let expectedPort = serverURL.port ?? (scheme.lowercased() == "https" ? 443 : 80)
        if let exact = resources.first(where: { resource in
            (resource.connections ?? []).contains { connection in
                connection.uri.host == host && connection.uri.port == expectedPort
            }
        }) {
            return exact
        }

        return resources.count == 1 ? resources.first : nil
    }
}