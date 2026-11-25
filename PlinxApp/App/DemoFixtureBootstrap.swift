import Foundation
import Observation
import UIKit

/// The App Review sample library: a credential-free session against a deterministic, loopback-only Plex-shaped
/// service (`DemoMediaServer`). Bundled media reaches the production HTTP playback and download clients, and the
/// session runs through the production `SessionManager`, `ServerRegistry` and `SafeMediaServices` boundary.
///
/// The sample library is a first-launch experience. It starts only while no account exists, so it never joins or
/// replaces a family's session, and it lives as a temporary Plex account (`PlexDirectSession`) that `stop()` removes
/// again. Its preferences and parental PIN stay in `DemoPreferences`.
enum DemoFixtureBootstrap {
    static let serverIdentifier = "plinx-demo-library"
    static let serverToken = "plinx-synthetic-review-token"
    /// Plex user of the sample account; its Home profile is the only demo profile.
    static let userUUID = "plinx-demo-family"
    #if DEBUG
        static let uiTestMode = "demo"
    #endif
    private static let serverName = "Plinx Demo Library"

    static var server: ServerIdentity {
        ServerIdentity(provider: .plex, id: serverIdentifier)
    }

    static var accountID: String {
        MediaAccount.plexID(userUUID)
    }

    static var profileID: String {
        PlexHomeProfile.id(userUUID: userUUID)
    }

    private static let stateLock = NSLock()
    private static var active = false
    @MainActor private static var isStarting = false
    @MainActor private static weak var activeSessionManager: SessionManager?

    /// True from the moment the sample library starts connecting until `stop()`. Readable from any thread.
    static var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return active
    }

    private static func setActive(_ value: Bool) {
        stateLock.lock()
        active = value
        stateLock.unlock()
    }

    /// The app is showing the sample library: the demo is running and its profile is the active one. This is the
    /// predicate for the demo's separate preferences, rating policy and PIN; it is observable through
    /// `SessionManager.activeProfile`.
    @MainActor
    static func isDemoSession(_ sessionManager: SessionManager) -> Bool {
        isActive && sessionManager.activeProfile?.id == profileID
    }

    // MARK: - Lifecycle

    /// Starts the sample library when no account exists yet. Success leaves `sessionManager.status == .ready` with
    /// the demo profile active and a registry session for `server`; on failure nothing of the demo remains.
    @MainActor
    static func start(sessionManager: SessionManager) async {
        guard !isStarting else { return }
        if isActive {
            // Already showing the sample library.
            if sessionManager.accountStore.account(id: accountID) != nil {
                return
            }
            // A parent removed the sample account from Settings: finish tearing the old demo down first.
            stop()
        }
        guard canStart(on: sessionManager) else { return }
        isStarting = true
        defer { isStarting = false }

        guard DemoSampleMedia.isAvailable,
              let serverURL = try? await DemoMediaServer.shared.start(),
              canStart(on: sessionManager),
              let session = PlexDirectSession(
                  userUUID: userUUID,
                  displayName: profileName,
                  token: serverToken,
                  serverName: serverName,
                  serverIdentifier: serverIdentifier,
                  serverURL: serverURL,
              )
        else {
            DemoMediaServer.shared.stop()
            return
        }

        DemoPreferences.reset()
        DemoFixtureCatalog.resetPlaybackState()
        DemoYoutarrCatalog.reset()
        DemoPreferences.configureYoutarr(baseURL: serverURL)

        activeSessionManager = sessionManager
        setActive(true)
        if await session.activate(on: sessionManager) {
            stopWhenAccountRemoved(from: sessionManager)
            return
        }
        stop()
    }

    /// A parent can also remove the sample account from the account settings; the demo then ends with it, so its
    /// listener and preferences never outlive the account into a family session.
    @MainActor
    private static func stopWhenAccountRemoved(from sessionManager: SessionManager) {
        withObservationTracking {
            _ = sessionManager.accountStore.accounts
        } onChange: {
            Task { @MainActor in
                guard isActive, activeSessionManager === sessionManager else { return }
                if sessionManager.accountStore.account(id: accountID) == nil {
                    stop()
                } else {
                    stopWhenAccountRemoved(from: sessionManager)
                }
            }
        }
    }

    /// Ends the sample library: removes its account (which leaves the session on account setup), its browsing
    /// cache, its plex.tv stand-in and the loopback listener. Sample downloads stay, owned by the demo profile.
    @MainActor
    static func stop() {
        if let sessionManager = activeSessionManager {
            #if !os(tvOS)
                let owner = sessionManager.registry.services(for: server)?.owner
                    ?? MediaOwner(server: server, userID: userUUID)
            #endif
            PlexDirectSession.removeAccount(userUUID: userUUID, from: sessionManager)
            #if !os(tvOS)
                OfflineCoordinator.shared.store?.clearCache(owner: owner)
            #endif
        }
        activeSessionManager = nil
        PlexCloudStandIn.unregister(token: serverToken)
        DemoMediaServer.shared.stop()
        DemoPreferences.parentalAccess.lock()
        setActive(false)
    }

    /// Removes a sample account that an interrupted launch (the app was quit or killed during the demo) left in the
    /// account stores, so hydration never activates a demo profile whose server is gone. Call it synchronously right
    /// after creating the `SessionManager`, before its hydration task runs.
    @MainActor
    static func discardInterruptedSession(from sessionManager: SessionManager) {
        guard !isActive, !isStarting,
              PlexDirectSession.hasAccount(userUUID: userUUID, in: sessionManager)
        else { return }
        PlexDirectSession.removeAccount(userUUID: userUUID, from: sessionManager)
    }

    /// Launch hook, called once right after the `SessionManager` is created: discards a sample account an
    /// interrupted launch left behind, then, in Debug builds only, starts the sample library when UI tests ask for it
    /// (`--ui-testing`, `PLINX_UI_TEST_MODE=demo`), so tvOS remote walkthroughs and screenshots start from a known
    /// library.
    @MainActor
    static func bootstrapForUITestIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String],
        sessionManager: SessionManager,
    ) {
        discardInterruptedSession(from: sessionManager)
        #if DEBUG
            guard arguments.contains("--ui-testing"),
                  environment["PLINX_UI_TEST_MODE"] == uiTestMode
            else { return }

            Task { @MainActor in
                while sessionManager.status == .hydrating {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                await start(sessionManager: sessionManager)
            }
        #endif
    }

    /// The demo never shares the session with a family account.
    @MainActor
    private static func canStart(on sessionManager: SessionManager) -> Bool {
        sessionManager.status == .needsAccount && sessionManager.accounts.isEmpty
    }

    private static var profileName: String {
        String(localized: "demo.profile.name", defaultValue: "Sample Family", table: "Plinx")
    }
}

// MARK: - Direct server session

/// A Plex server reached at a known address with no plex.tv account behind it: the App Review sample library and the
/// live UI-test server. `SessionManager` reaches Plex servers only through plex.tv accounts, so the session is a
/// temporary Plex account whose single Home user owns `resource`. Its token, cached resources and Home user are
/// written to the session's stores, and every plex.tv request carrying the token is answered on the device by
/// `PlexCloudStandIn`, so the token never leaves the device and the session needs no host but the server itself.
@MainActor
struct PlexDirectSession {
    let userUUID: String
    let displayName: String
    let token: String
    let resource: PlexCloudResource

    init?(
        userUUID: String,
        displayName: String,
        token: String,
        serverName: String,
        serverIdentifier: String,
        serverURL: URL,
    ) {
        guard let scheme = serverURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = serverURL.host, !host.isEmpty, !token.isEmpty
        else { return nil }
        let connection = PlexCloudResource.Connection(
            scheme: scheme,
            address: host,
            port: serverURL.port ?? (scheme == "https" ? 443 : 80),
            uri: serverURL,
            isLocal: true,
            isRelay: false,
            isIPv6: host.contains(":"),
        )
        self.userUUID = userUUID
        self.displayName = displayName
        self.token = token
        // Not owned: the account administers nothing, so server management never shows for these sessions.
        resource = PlexCloudResource(
            name: serverName,
            clientIdentifier: serverIdentifier,
            accessToken: token,
            connections: [connection],
            owned: false,
            provides: "server",
        )
    }

    var accountID: String {
        MediaAccount.plexID(userUUID)
    }

    var profileID: String {
        PlexHomeProfile.id(userUUID: userUUID)
    }

    var server: ServerIdentity {
        ServerIdentity(provider: .plex, id: resource.clientIdentifier)
    }

    var homeUser: PlexHomeUser {
        PlexHomeUser(
            id: 1,
            uuid: userUUID,
            title: displayName,
            username: nil,
            email: nil,
            friendlyName: displayName,
            thumb: nil,
            protected: false,
            pin: nil,
            admin: true,
            guest: false,
            restricted: false,
        )
    }

    var cloudUser: PlexCloudUser {
        PlexCloudUser(
            id: 1,
            uuid: userUUID,
            username: nil,
            title: displayName,
            friendlyName: displayName,
            authToken: token,
            thumb: nil,
        )
    }

    /// Starts answering for the token, then writes (or refreshes) the account, its server and its Home user in the
    /// session's stores. Done before hydration, it lets hydration resume the profile like any other.
    @discardableResult
    func store(in sessionManager: SessionManager) -> Bool {
        PlexCloudStandIn.register(self)
        do {
            try sessionManager.accountStore.save(
                .plex(PlexAccount(id: userUUID, displayName: displayName)),
                token: token,
            )
        } catch {
            return false
        }
        sessionManager.accountStore.setCachedResources([resource], userUUID: userUUID)
        sessionManager.profileStore.updatePlexHomeUsers([homeUser], accountID: accountID)
        sessionManager.profileStore.setDefaultServerSelection(.only([resource.clientIdentifier]), accountID: accountID)
        return true
    }

    /// Stores the account, activates its profile unless it is already the active one, and waits for the server.
    /// Returns `true` once the server's services exist.
    func activate(on sessionManager: SessionManager, timeout: Duration = .seconds(10)) async -> Bool {
        guard store(in: sessionManager),
              let profile = sessionManager.profiles.first(where: { $0.id == profileID })
        else { return false }
        if sessionManager.activeProfile?.id != profileID {
            await sessionManager.activate(profile)
        }
        return await waitForServices(on: sessionManager, timeout: timeout)
    }

    /// Services exist once the server answered; readiness is read from them rather than from reachability, which
    /// reports a loopback server as unreachable while the device has no network path.
    private func waitForServices(on sessionManager: SessionManager, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while sessionManager.activeProfile?.id == profileID, !Task.isCancelled {
            if sessionManager.registry.services(for: server) != nil {
                return true
            }
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    static func hasAccount(userUUID: String, in sessionManager: SessionManager) -> Bool {
        let accountID = MediaAccount.plexID(userUUID)
        return sessionManager.accountStore.account(id: accountID) != nil
            || !sessionManager.profileStore.plexHomeUsers(accountID: accountID).isEmpty
    }

    /// Removing the account deactivates its profile when it is the active one: the session then lands on account
    /// setup, or on the profile picker when other accounts exist.
    static func removeAccount(userUUID: String, from sessionManager: SessionManager) {
        let accountID = MediaAccount.plexID(userUUID)
        if sessionManager.accountStore.account(id: accountID) != nil {
            sessionManager.removeAccount(accountID)
        } else if !sessionManager.profileStore.plexHomeUsers(accountID: accountID).isEmpty {
            sessionManager.profileStore.removeAccount(accountID)
        }
        sessionManager.accountStore.removeHomeToken(accountID: accountID, userUUID: userUUID)
        sessionManager.accountStore.removeCachedResources(userUUID: userUUID)
    }
}

// MARK: - plex.tv stand-in

/// Answers on the device every plex.tv request made with the token of a `PlexDirectSession`: the resources (its one
/// server), the account, its Home users and account preferences. Anything else, such as the watchlist, is refused
/// here rather than sent: these sessions have no plex.tv account, and their token must not leave the device.
/// Requests carrying any other token, and sign-in requests carrying none, are never touched.
final class PlexCloudStandIn: URLProtocol {
    private struct Registration {
        let userUUID: String
        let user: Data
        let home: Data
        let resources: Data
    }

    private static let lock = NSLock()
    private static var registrations: [String: Registration] = [:]
    private static var isRegisteredWithURLLoading = false

    @MainActor
    static func register(_ session: PlexDirectSession) {
        let encoder = JSONEncoder()
        let registration = Registration(
            userUUID: session.userUUID,
            user: (try? encoder.encode(session.cloudUser)) ?? Data("{}".utf8),
            home: (try? encoder.encode(PlexHome(users: [session.homeUser]))) ?? Data(#"{"users":[]}"#.utf8),
            resources: (try? encoder.encode([session.resource])) ?? Data("[]".utf8),
        )
        lock.lock()
        registrations[session.token] = registration
        let needsRegistration = !isRegisteredWithURLLoading
        isRegisteredWithURLLoading = true
        lock.unlock()
        if needsRegistration {
            URLProtocol.registerClass(self)
        }
    }

    static func unregister(token: String) {
        lock.lock()
        registrations[token] = nil
        let isEmpty = registrations.isEmpty
        let needsUnregistration = isEmpty && isRegisteredWithURLLoading
        if needsUnregistration {
            isRegisteredWithURLLoading = false
        }
        lock.unlock()
        if needsUnregistration {
            URLProtocol.unregisterClass(self)
        }
    }

    private static func registration(for request: URLRequest) -> Registration? {
        guard isPlexCloudHost(request.url?.host), let token = token(of: request) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return registrations[token]
    }

    static func isPlexCloudHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "plex.tv" || host.hasSuffix(".plex.tv")
    }

    private static func token(of request: URLRequest) -> String? {
        if let header = request.value(forHTTPHeaderField: "X-Plex-Token"), !header.isEmpty {
            return header
        }
        guard let url = request.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "X-Plex-Token" }?
            .value
    }

    /// Status and body for a request; `nil` when the request is not one this stand-in answers.
    static func response(for request: URLRequest) -> (statusCode: Int, body: Data)? {
        guard let registration = registration(for: request), let url = request.url else { return nil }
        var path = url.path
        if path.hasPrefix("/api/v2/") {
            path.removeFirst("/api/v2".count)
        }
        let method = (request.httpMethod ?? "GET").uppercased()
        switch (method, path) {
        case ("GET", "/resources"):
            return (200, registration.resources)
        case ("GET", "/user"):
            return (200, registration.user)
        case ("GET", "/home/users"):
            return (200, registration.home)
        case let ("POST", value) where value == "/home/users/\(registration.userUUID)/switch":
            return (200, registration.user)
        case ("GET", "/user/profile"):
            return (200, Data("{}".utf8))
        case ("PUT", "/user/profile"):
            return (200, Data("{}".utf8))
        case let ("GET", value) where value.hasPrefix("/library/metadata/") && value.hasSuffix("/userState"):
            return (200, Data(#"{"MediaContainer":{"size":0,"UserState":[]}}"#.utf8))
        default:
            return (404, Data(#"{"error":"Not available without a plex.tv account"}"#.utf8))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        registration(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // A token unregistered since `canInit` is refused here too: it must not reach plex.tv either way.
        guard let url = request.url,
              let result = Self.response(for: request),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: result.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: [
                      "Content-Type": "application/json",
                      "Content-Length": String(result.body.count),
                      "Cache-Control": "no-store",
                  ],
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Sample catalog

/// Plex Media Server responses of the sample library, served by `DemoMediaServer`. Only the path and query of a
/// request matter, never its host.
enum DemoFixtureCatalog {
    private struct Record {
        let id: String
        let title: String
        let rating: String
        let year: Int
        let summary: String
        let type: String
        let sectionID: Int
        let viewOffset: Int?
    }

    private static let movies = [
        Record(id: "moonbound", title: "Moonbound", rating: "PG", year: 2026, summary: "A family science adventure.", type: "movie", sectionID: 1, viewOffset: 20_000),
        Record(id: "cloud-chasers", title: "Cloud Chasers", rating: "PG", year: 2025, summary: "Young weather watchers follow a summer storm.", type: "movie", sectionID: 1, viewOffset: 30_000),
        Record(id: "big-build", title: "The Big Build", rating: "PG", year: 2024, summary: "Friends transform an empty lot into a community workshop.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "hidden-gardens", title: "Hidden Gardens", rating: "G", year: 2023, summary: "A gentle tour of surprising gardens around the world.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "robot-club", title: "Robot Club", rating: "PG", year: 2026, summary: "A school robotics team learns to build together.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "lighthouse-map", title: "The Lighthouse Map", rating: "PG", year: 2025, summary: "Siblings follow clues along a quiet coast.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "paper-airship", title: "The Paper Airship", rating: "G", year: 2024, summary: "A classroom invention takes an unexpected journey.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "river-trail", title: "The River Trail", rating: "PG", year: 2026, summary: "Friends learn to read a landscape together.", type: "movie", sectionID: 1, viewOffset: nil),
    ]

    private static let safetyExamples = [
        Record(id: "rating-example", title: "Rating Limit Example", rating: "PG-13", year: 2026, summary: "Safe abstract sample, labeled PG-13 to demonstrate rating controls.", type: "movie", sectionID: 1, viewOffset: nil),
        Record(id: "unrated-example", title: "Unrated Example", rating: "", year: 2026, summary: "Safe abstract sample without a content rating, for testing unrated exclusion.", type: "movie", sectionID: 1, viewOffset: nil),
    ]

    private static let shows = [
        Record(id: "space-camp", title: "Space Camp", rating: "TV-PG", year: 2026, summary: "Young explorers train for a mission beyond Earth.", type: "show", sectionID: 2, viewOffset: 20_000),
        Record(id: "kitchen-lab", title: "Kitchen Lab", rating: "TV-G", year: 2025, summary: "Every recipe becomes a friendly science experiment.", type: "show", sectionID: 2, viewOffset: 30_000),
        Record(id: "wild-neighbors", title: "Wild Neighbors", rating: "TV-PG", year: 2024, summary: "Families discover the animals living close to home.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "makers-next-door", title: "Makers Next Door", rating: "TV-G", year: 2025, summary: "Creative neighbors share practical projects.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "junior-rangers", title: "Junior Rangers", rating: "TV-G", year: 2026, summary: "Young naturalists care for a neighborhood park.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "story-station", title: "Story Station", rating: "TV-PG", year: 2025, summary: "A book club turns stories into weekend adventures.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "music-room", title: "The Music Room", rating: "TV-G", year: 2024, summary: "Friends explore instruments and sounds.", type: "show", sectionID: 2, viewOffset: nil),
        Record(id: "market-day", title: "Market Day", rating: "TV-PG", year: 2026, summary: "A community market becomes a lesson in teamwork.", type: "show", sectionID: 2, viewOffset: nil),
    ]

    // These labels are deliberate test metadata. Every item plays the same
    // safe abstract sample, including those labeled with a higher rating.
    private static let ratingTestMovies: [Record] = [
        ("g", "G"), ("pg", "PG"), ("pg13", "PG-13"), ("r", "R"), ("unrated", ""),
    ].map { key, rating in
        Record(id: "rating-movie-\(key)", title: "Movie Sample - \(rating.isEmpty ? "Unrated" : rating)",
               rating: rating, year: 2026,
               summary: "Safe abstract video with synthetic rating metadata for testing parental filters.",
               type: "movie", sectionID: 4, viewOffset: nil)
    }

    private static let ratingTestTV: [Record] = [
        ("tvy", "TV-Y"), ("tvy7", "TV-Y7"), ("tvg", "TV-G"), ("tvpg", "TV-PG"),
        ("tv14", "TV-14"), ("tvma", "TV-MA"), ("unrated", ""),
    ].map { key, rating in
        Record(id: "rating-tv-\(key)", title: "TV Sample - \(rating.isEmpty ? "Unrated" : rating)",
               rating: rating, year: 2026,
               summary: "Safe abstract episodes with synthetic rating metadata for testing parental filters.",
               type: "show", sectionID: 5, viewOffset: nil)
    }

    private static var allShows: [Record] { shows + ratingTestTV }

    private static let otherVideos = [
        Record(id: "bridge-basics", title: "How Bridges Work", rating: "PG", year: 2026, summary: "A friendly look at bridge design.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "backyard-sky", title: "Backyard Astronomy", rating: "PG", year: 2026, summary: "A beginner guide to the night sky.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "tiny-garden", title: "Make a Tiny Garden", rating: "G", year: 2026, summary: "A small growing project for families.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "science-sound", title: "The Science of Sound", rating: "PG", year: 2026, summary: "Experiments with rhythm and vibration.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "friendly-dragons", title: "Drawing Friendly Dragons", rating: "G", year: 2026, summary: "A playful step-by-step drawing lesson.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "bird-feeder", title: "Build a Bird Feeder", rating: "G", year: 2026, summary: "A simple project for welcoming backyard birds.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "cloud-journal", title: "Start a Cloud Journal", rating: "PG", year: 2026, summary: "Learn to notice and record changing skies.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "paper-circuits", title: "Make a Paper Circuit", rating: "PG", year: 2026, summary: "Light up a drawing with a beginner circuit.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "bread-science", title: "The Science of Bread", rating: "G", year: 2026, summary: "See how simple ingredients change as dough rises.", type: "movie", sectionID: 3, viewOffset: nil),
        Record(id: "map-compass", title: "Maps and Compasses", rating: "PG", year: 2026, summary: "Practice basic navigation on a family walk.", type: "movie", sectionID: 3, viewOffset: nil),
    ]

    private static var allRecords: [Record] {
        movies + safetyExamples + allShows + otherVideos + ratingTestMovies
    }

    private static let stateLock = NSLock()
    private static var queues: [Int: [String: Any]] = [:]
    private static var nextQueueID = 1
    private static var positions: [String: Int] = [:]

    static func resetPlaybackState() {
        stateLock.lock()
        defer { stateLock.unlock() }
        queues.removeAll()
        positions.removeAll()
        nextQueueID = 1
    }

    static func artworkPNG(path: String) -> Data {
        let landscape = path.contains("backdrop")
        let size = landscape ? CGSize(width: 640, height: 360) : CGSize(width: 240, height: 360)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor(red: 0.06, green: 0.22, blue: 0.25, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.64, green: 0.82, blue: 0.43, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.25, y: 90, width: 120, height: 120))
            let title = "PLINX\nSAMPLE LIBRARY" as NSString
            title.draw(in: CGRect(x: 20, y: 250, width: size.width - 40, height: 90),
                       withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])
        }
    }

    static func response(for request: URLRequest) -> DemoFixtureResponse {
        guard let url = request.url else {
            return DemoFixtureResponse(statusCode: 400, mimeType: "application/json", data: jsonData(["error": "missing URL"]))
        }

        let path = url.path
        if path.hasPrefix("/external-api/v1/") { return DemoYoutarrCatalog.response(for: request) }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let method = request.httpMethod?.uppercased() ?? "GET"

        switch (method, path) {
        case (_, "/"):
            return json(["MediaContainer": [:]])
        case (_, "/library/sections/all"):
            return json([
                "MediaContainer": [
                    "size": 5,
                    "Directory": [
                        ["agent": "tv.plex.agents.movie", "key": "1", "type": "movie", "title": "Family Movies"],
                        ["agent": "tv.plex.agents.series", "key": "2", "type": "show", "title": "Family TV"],
                        ["agent": "tv.plex.agents.none", "key": "3", "type": "movie", "title": "Learning Videos"],
                        ["agent": "tv.plex.agents.movie", "key": "4", "type": "movie", "title": "Rating Test Movies"],
                        ["agent": "tv.plex.agents.series", "key": "5", "type": "show", "title": "Rating Test TV"],
                    ],
                ],
            ])
        case (_, "/hubs/continueWatching"):
            let continueItems = [shows[0], shows[1], movies[0], shows[2], movies[1], shows[4]].map(itemJSON)
            return hubResponse(title: "Continue Watching", identifier: "continueWatching", items: continueItems)
        case (_, "/hubs/promoted"):
            let items = (Array(movies.prefix(6)) + Array(shows.prefix(6))).map(itemJSON)
            return hubResponse(title: "Recently Added", identifier: "recentlyAdded", items: items)
        case (_, let value) where value.hasPrefix("/hubs/sections/"):
            let sectionID = value.split(separator: "/").last.flatMap { Int($0) } ?? 1
            let records = recordsForSection(sectionID)
            return hubResponse(title: "Recommended", identifier: "recommended-\(sectionID)", items: records.map(itemJSON))
        case (_, "/library/search"):
            let searchText = query.first(where: { $0.name == "query" })?.value?.lowercased() ?? ""
            let results = allRecords
                .filter { searchText.isEmpty || $0.title.lowercased().contains(searchText) }
                .map { ["score": 1.0, "Metadata": itemJSON($0)] }
            return json(["MediaContainer": ["size": results.count, "SearchResult": results]])
        case (_, let value) where value.hasPrefix("/library/sections/") && value.hasSuffix("/all"):
            let components = value.split(separator: "/")
            let sectionID = components.dropFirst(2).first.flatMap { Int($0) } ?? 1
            let records = recordsForSection(sectionID)
            return itemContainer(records.map(itemJSON))
        case (_, let value) where value.hasPrefix("/library/sections/") && value.hasSuffix("/collections"):
            return itemContainer([groupJSON(type: "collection")])
        case (_, "/playlists"):
            return itemContainer([groupJSON(type: "playlist")])
        case (_, "/playlists/demo-mix/items"), (_, "/library/collections/demo-mix/children"):
            return itemContainer(([movies[0], movies[3]] + safetyExamples).map(itemJSON))
        case (_, "/playlists/demo-mix"):
            return itemContainer([groupJSON(type: "playlist")])
        case (_, "/library/collections/demo-mix"):
            return itemContainer([groupJSON(type: "collection")])
        case (_, let value) where value.hasPrefix("/library/metadata/") && value.hasSuffix("/related"):
            let rawID = String(value.dropFirst("/library/metadata/".count))
            let id = String(rawID.dropLast("/related".count))
            let source = allRecords.first(where: { $0.id == id })
            let related = allRecords
                .filter { $0.id != id && $0.type == source?.type }
                .prefix(6)
                .map(itemJSON)
            return hubResponse(title: "More Like This", identifier: "related-\(id)", items: related)
        case (_, let value) where value.hasPrefix("/library/metadata/") && value.hasSuffix("/extras"):
            return itemContainer([])
        case (_, let value) where value.hasPrefix("/library/people/"):
            return personResponse(for: String(value.dropFirst("/library/people/".count)))
        case (_, let value) where value.hasPrefix("/library/metadata/"):
            return metadataResponse(for: String(value.dropFirst("/library/metadata/".count)))
        case (_, let value) where value.hasPrefix("/library/collections/") || value.hasPrefix("/playlists"):
            return itemContainer([])
        case ("GET", let value) where value.hasPrefix("/video/"):
            return videoResponse(path: value)
        case ("HEAD", let value) where value.hasPrefix("/video/"):
            return videoResponse(path: value)
        case (_, "/photo/:/transcode"):
            return DemoFixtureResponse(statusCode: 200, mimeType: "image/png", data: artworkPNG(path: url.absoluteString))
        case (_, let value) where value.hasPrefix("/artwork/"):
            return DemoFixtureResponse(statusCode: 200, mimeType: "image/png", data: artworkPNG(path: url.absoluteString))
        case ("POST", "/playQueues"):
            let requestedID = query.first(where: { $0.name == "uri" })?.value?.split(separator: "/").last.map(String.init)
            guard let requestedID else { return itemContainer([]) }
            let selected: [String: Any]
            if let record = allRecords.first(where: { $0.id == requestedID }) {
                if record.type == "show" {
                    selected = episodeJSON(showID: record.id, season: 1, episode: 1)
                } else {
                    selected = itemJSON(record)
                }
            } else if let episode = episodeIDParts(requestedID) {
                selected = episodeJSON(showID: episode.showID, season: episode.season, episode: episode.episode)
            } else if let season = seasonIDParts(requestedID) {
                selected = episodeJSON(showID: season.showID, season: season.index, episode: 1)
            } else {
                return itemContainer([])
            }
            let queueItems = [selected.merging(["playQueueItemID": 1]) { current, _ in current }]
            stateLock.lock()
            let queueID = nextQueueID
            nextQueueID += 1
            let container: [String: Any] = [
                "size": queueItems.count, "playQueueID": queueID, "playQueueSelectedItemID": 1,
                "playQueueSelectedMetadataItemID": selected["ratingKey"] ?? requestedID,
                "playQueueTotalCount": queueItems.count, "playQueueVersion": 1, "Metadata": queueItems,
            ]
            queues[queueID] = container
            stateLock.unlock()
            return json(["MediaContainer": container])
        case (_, let value) where value.hasPrefix("/playQueues/"):
            let queueID = value.split(separator: "/").last.flatMap { Int($0) } ?? 0
            stateLock.lock()
            let container = queues[queueID]
            stateLock.unlock()
            return json(["MediaContainer": container ?? ["playQueueID": queueID, "playQueueTotalCount": 0, "Metadata": []]])
        case (_, "/:/timeline"):
            if let id = query.first(where: { $0.name == "ratingKey" })?.value,
               let time = query.first(where: { $0.name == "time" })?.value.flatMap(Int.init) {
                stateLock.lock()
                positions[id] = min(max(0, time), DemoSampleMedia.durationMilliseconds)
                stateLock.unlock()
            }
            return json(["MediaContainer": [:]])
        case (_, "/:/scrobble"), (_, "/:/unscrobble"), (_, "/library/parts/1"):
            return json(["MediaContainer": [:]])
        default:
            return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "demo fixture endpoint not found", "path": path]))
        }
    }

    /// The two fictional cast members every sample title credits, and the titles they appear in.
    private static let cast = [1: "Avery North", 2: "Jordan Vale"]

    private static func personResponse(for rawID: String) -> DemoFixtureResponse {
        let parts = rawID.split(separator: "/")
        guard let id = parts.first.flatMap({ Int($0) }), let name = cast[id] else {
            return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "unknown demo person"]))
        }
        if parts.count == 2, parts[1] == "media" {
            let titles = id == 1 ? Array(movies.prefix(4)) + Array(shows.prefix(2)) : Array(movies.suffix(4)) + Array(shows.suffix(2))
            return itemContainer(titles.map(itemJSON))
        }
        guard parts.count == 1 else {
            return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "unknown demo person"]))
        }
        return json(["MediaContainer": ["size": 1, "Directory": [["id": id, "tag": name, "tagType": 6]]]])
    }

    private static func recordsForSection(_ sectionID: Int) -> [Record] {
        switch sectionID {
        case 1: movies + safetyExamples
        case 2: shows
        case 3: otherVideos
        case 4: ratingTestMovies
        case 5: ratingTestTV
        default: []
        }
    }

    private static func itemJSON(_ record: Record) -> [String: Any] {
        var item: [String: Any] = [
            "ratingKey": record.id,
            "key": "/library/metadata/\(record.id)",
            "guid": "plex://fixture/\(record.id)",
            "librarySectionID": record.sectionID,
            "type": record.type,
            "title": record.title,
            "summary": record.summary,
            "thumb": "/artwork/poster/\(record.id).png",
            "art": "/artwork/backdrop/\(record.id).png",
            "year": record.year,
            "duration": DemoSampleMedia.durationMilliseconds,
            "contentRating": record.rating,
            "studio": "Plinx Fixture Studio",
            "tagline": "Curiosity starts close to home.",
            "audienceRating": 8.4,
            "rating": 8.1,
            "Genre": [["tag": "Family"], ["tag": "Adventure"]],
            "Role": [["id": 1, "tag": "Avery North"], ["id": 2, "tag": "Jordan Vale"]],
            "Media": [[
                "id": 1,
                "videoResolution": "sd",
                "container": "mp4",
                "videoCodec": "h264",
                "audioCodec": "aac",
                "width": 640,
                "height": 360,
                "Part": [["id": 1, "key": "/video/\(record.id).mp4", "size": DemoSampleMedia.byteCount(isEpisode: record.type == "episode")]],
            ]],
        ]
        stateLock.lock()
        let viewOffset = positions[record.id] ?? record.viewOffset
        stateLock.unlock()
        if let viewOffset, viewOffset < DemoSampleMedia.durationMilliseconds {
            item["viewOffset"] = viewOffset
        }
        if record.rating.isEmpty { item.removeValue(forKey: "contentRating") }
        if record.type == "show" {
            item["childCount"] = 2
            item["leafCount"] = 4
            item["viewedLeafCount"] = 1
        }
        return item
    }

    private static func metadataResponse(for rawID: String) -> DemoFixtureResponse {
        let id = rawID.split(separator: "/").first.map(String.init) ?? rawID
        if id == "demo-mix" {
            if rawID.hasSuffix("/children") {
                return itemContainer(([movies[0], movies[3]] + safetyExamples).map(itemJSON))
            }
            return itemContainer([groupJSON(type: "collection")])
        }
        if rawID.hasSuffix("/children") {
            let parentID = id
            if let show = allShows.first(where: { $0.id == parentID }) {
                return itemContainer((1...2).map { seasonJSON(show: show, index: $0) })
            }
            if let season = seasonIDParts(parentID) {
                return itemContainer((1...2).map { episodeJSON(showID: season.showID, season: season.index, episode: $0) })
            }
            return itemContainer([])
        }
        if rawID.hasSuffix("/grandchildren") {
            guard let show = allShows.first(where: { $0.id == id }) else { return itemContainer([]) }
            let episodes = (1...2).flatMap { season in
                (1...2).map { episodeJSON(showID: show.id, season: season, episode: $0) }
            }
            return itemContainer(episodes)
        }
        if let record = allRecords.first(where: { $0.id == id }) {
            return itemContainer([itemJSON(record)])
        }
        if let season = seasonIDParts(id) {
            return itemContainer([seasonJSON(show: allShows.first(where: { $0.id == season.showID }) ?? shows[0], index: season.index)])
        }
        if let episode = episodeIDParts(id) {
            return itemContainer([episodeJSON(showID: episode.showID, season: episode.season, episode: episode.episode)])
        }
        return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "unknown demo media"]))
    }

    private static func seasonIDParts(_ id: String) -> (showID: String, index: Int)? {
        let parts = id.split(separator: "-")
        guard parts.count >= 3, parts[parts.count - 2] == "season", let index = Int(parts.last!) else { return nil }
        let showID = parts.dropLast(2).joined(separator: "-")
        guard (1...2).contains(index), allShows.contains(where: { $0.id == showID }) else { return nil }
        return (showID, index)
    }

    private static func episodeIDParts(_ id: String) -> (showID: String, season: Int, episode: Int)? {
        let parts = id.split(separator: "-")
        guard parts.count >= 5,
              parts[parts.count - 4] == "season",
              parts[parts.count - 2] == "e",
              let season = Int(parts[parts.count - 3]),
              let episode = Int(parts.last!)
        else { return nil }
        let showID = parts.dropLast(4).joined(separator: "-")
        guard (1...2).contains(season), (1...2).contains(episode),
              allShows.contains(where: { $0.id == showID }) else { return nil }
        return (showID, season, episode)
    }

    private static func seasonJSON(show: Record, index: Int) -> [String: Any] {
        var item: [String: Any] = [
            "ratingKey": "\(show.id)-season-\(index)",
            "key": "/library/metadata/\(show.id)-season-\(index)",
            "guid": "plex://fixture/\(show.id)-season-\(index)",
            "type": "season",
            "title": "Season \(index)",
            "parentRatingKey": show.id,
            "parentTitle": show.title,
            "parentIndex": index,
            "thumb": "/artwork/poster/\(show.id).png",
            "art": "/artwork/backdrop/\(show.id).png",
            "contentRating": show.rating,
            "childCount": 2,
            "librarySectionID": show.sectionID,
        ]
        if show.rating.isEmpty { item.removeValue(forKey: "contentRating") }
        return item
    }

    private static func episodeJSON(showID: String, season: Int, episode: Int) -> [String: Any] {
        let show = allShows.first(where: { $0.id == showID }) ?? shows[0]
        let id = "\(showID)-season-\(season)-e-\(episode)"
        var item: [String: Any] = [
            "ratingKey": id,
            "key": "/library/metadata/\(id)",
            "guid": "plex://fixture/\(id)",
            "type": "episode",
            "librarySectionID": show.sectionID,
            "title": "Episode \(episode)",
            "summary": "A fictional episode from the Plinx review fixture.",
            "parentRatingKey": "\(showID)-season-\(season)",
            "parentTitle": "Season \(season)",
            "parentIndex": season,
            "grandparentRatingKey": showID,
            "grandparentTitle": show.title,
            "grandparentThumb": "/artwork/poster/\(showID).png",
            "grandparentArt": "/artwork/backdrop/\(showID).png",
            "index": episode,
            "duration": DemoSampleMedia.durationMilliseconds,
            "contentRating": show.rating,
            "thumb": "/artwork/poster/\(showID).png",
            "art": "/artwork/backdrop/\(showID).png",
            "Media": [[
                "id": 1,
                "videoResolution": "sd",
                "container": "mp4",
                "videoCodec": "h264",
                "audioCodec": "aac",
                "width": 640,
                "height": 360,
                "Part": [["id": 1, "key": "/video/\(id).mp4", "size": DemoSampleMedia.byteCount(isEpisode: true)]],
            ]],
        ]
        if show.rating.isEmpty { item.removeValue(forKey: "contentRating") }
        return item
    }

    private static func groupJSON(type: String) -> [String: Any] {
        ["ratingKey": "demo-mix", "key": type == "playlist" ? "/playlists/demo-mix/items" : "/library/collections/demo-mix/children",
         "type": type, "title": "Mixed Ratings Sample", "playlistType": "video", "smart": false,
         "summary": "Includes allowed, PG-13, and unrated examples. All sample videos contain safe abstract graphics.",
         "leafCount": 4, "childCount": 4, "thumb": "/artwork/poster/moonbound.png"]
    }

    private static func videoResponse(path: String) -> DemoFixtureResponse {
        let id = String(path.dropFirst("/video/".count).dropLast(4))
        guard path.hasSuffix(".mp4"),
              allRecords.contains(where: { $0.id == id && $0.type != "show" }) || episodeIDParts(id) != nil,
              let data = DemoSampleMedia.data(isEpisode: episodeIDParts(id) != nil) else {
            return DemoFixtureResponse(statusCode: 404, mimeType: "application/json", data: jsonData(["error": "unknown demo video"]))
        }
        return DemoFixtureResponse(statusCode: 200, mimeType: "video/mp4", data: data)
    }

    private static func hubResponse(title: String, identifier: String, items: [[String: Any]]) -> DemoFixtureResponse {
        json([
            "MediaContainer": [
                "size": 1,
                "Hub": [[
                    "hubKey": "/hubs/\(identifier)",
                    "key": "/hubs/\(identifier)",
                    "title": title,
                    "hubIdentifier": identifier,
                    "size": items.count,
                    "more": false,
                    "Metadata": items,
                ]],
            ],
        ])
    }

    private static func itemContainer(_ items: [[String: Any]]) -> DemoFixtureResponse {
        json(["MediaContainer": ["size": items.count, "totalSize": items.count, "Metadata": items]])
    }

    private static func json(_ object: Any) -> DemoFixtureResponse {
        DemoFixtureResponse(statusCode: 200, mimeType: "application/json", data: jsonData(object))
    }

    private static func jsonData(_ object: Any) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return data
    }
}

struct DemoFixtureResponse {
    let statusCode: Int
    let mimeType: String
    let data: Data
}
