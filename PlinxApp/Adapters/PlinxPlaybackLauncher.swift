import Foundation
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// PlaybackLauncher — the one way playback starts, and its final safety check
// ─────────────────────────────────────────────────────────────────────────────
//
// Every caller starts playback here: the Plinx shell (through
// `PlaybackLaunchCoordinator`), the card menus, the reachable-copy button and
// incoming SharePlay sessions. `SafeMediaServices` already filters every queue
// a provider returns; this launcher is the last check before the player opens
// and fails closed on anything it cannot verify:
//   • the starting title is fetched again and must be allowed;
//   • every member of the queue must be allowed (`.blocked` otherwise);
//   • request failures, empty queues and cancelled launches never present.
// Its `gate` decides: the shared gate, which follows the parent's settings and
// knows the series ratings seasons and episodes are judged against. A caller
// that must check against another policy passes `ContentSafetyGate(policy:)`.
// A downloaded copy plays only when it is the active profile's own and
// `DownloadAccessPolicy` allows it (stored and pinned metadata both pass).
// The downloads and server reachability come from an `OfflinePlaybackSource`
// (the app's offline stack; tests give their own), but the launcher makes
// those checks itself, whatever the source returns.
//
// External players are never used: handing a title to another app bypasses
// the content checks and the volume cap, so the launcher has no option for
// one and the provider protocols offer no URL for one.
//
// `PlaybackLauncherTests` covers every rule above.
//
// ─────────────────────────────────────────────────────────────────────────────

/// What the launcher needs from the app's coordinator to present the player.
@MainActor
protocol PlaybackPresenting: AnyObject {
    func showPlayer(
        for queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool,
        notice: String?,
    )
    #if !os(tvOS)
        func showLocalPlayer(_ request: LocalPlaybackRequest)
    #endif
}

#if !os(tvOS)
    /// Where the launcher finds a downloaded copy while a server is unreachable. It only supplies data: the launcher
    /// still checks the download's owner and content itself.
    @MainActor
    protocol OfflinePlaybackSource {
        func isUnreachable(_ server: ServerIdentity) -> Bool
        /// A completed download of a movie, episode or clip, or the next downloaded episode of a series or season,
        /// with the request that plays it.
        func downloadedPlayback(
            for identity: MediaIdentity,
            kind: MediaKind,
            resumes: Bool,
        ) -> (request: LocalPlaybackRequest, download: DownloadItem)?
        /// The owners whose downloads the active profile may play.
        var activeOwnerIDs: Set<String> { get }
        /// Server metadata pinned for a download, judged together with the metadata stored with it.
        func pinnedMedia(for download: DownloadItem) -> MediaItem?
    }

    /// The app's offline stack: `OfflineCoordinator` for reachability, `DownloadManager` for the downloads.
    struct AppOfflinePlaybackSource: OfflinePlaybackSource {
        func isUnreachable(_ server: ServerIdentity) -> Bool {
            OfflineCoordinator.shared.isUnreachable(server)
        }

        func downloadedPlayback(
            for identity: MediaIdentity,
            kind: MediaKind,
            resumes: Bool,
        ) -> (request: LocalPlaybackRequest, download: DownloadItem)? {
            // `localPlaybackRequest(for:kind:)` only picks among the active profile's own completed downloads.
            guard let downloads = DownloadManager.shared,
                  let request = downloads.localPlaybackRequest(for: identity, kind: kind, resumes: resumes),
                  let download = downloads.ownedItems.first(where: {
                      $0.status == .completed
                          && $0.identity?.server == identity.server
                          && $0.itemID == request.media.id
                  })
            else { return nil }
            return (request, download)
        }

        var activeOwnerIDs: Set<String> {
            DownloadManager.shared?.activeOwnerIDs ?? []
        }

        func pinnedMedia(for download: DownloadItem) -> MediaItem? {
            DownloadManager.shared?.playbackMedia(for: download)
        }
    }
#endif

@MainActor
struct PlaybackLauncher {
    enum Result: Equatable {
        case started
        case blocked
        case failed
    }

    let services: MediaServices
    let coordinator: any PlaybackPresenting
    /// Judges every title the launcher could play.
    let gate: ContentSafetyGate
    #if !os(tvOS)
        /// The app's offline stack unless replaced with `using(offline:)`.
        private(set) var offline: any OfflinePlaybackSource
    #endif

    /// - Parameter gate: the shared gate when `nil` (resolved on the main actor, unlike a default argument). Pass
    ///   `ContentSafetyGate(policy:)` to judge titles against another policy.
    init(
        services: MediaServices,
        coordinator: any PlaybackPresenting,
        gate: ContentSafetyGate? = nil,
    ) {
        self.services = services
        self.coordinator = coordinator
        self.gate = gate ?? .shared
        #if !os(tvOS)
            offline = AppOfflinePlaybackSource()
        #endif
    }

    /// Plays a title, or the next episode of a series or season.
    /// - Parameter shouldContinue: checked right before presenting, so a cancelled launch never opens the player.
    @discardableResult
    func play(
        ratingKey: String,
        type: MediaKind,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true,
        shouldContinue: @escaping @MainActor () -> Bool = { true },
    ) async -> Result {
        ThemeMusicPlayer.shared.silence()
        #if !os(tvOS)
            // Without the server, the downloaded copy is played instead of streaming.
            if !shuffle, offline.isUnreachable(services.identity) {
                return playDownloadedChecked(
                    ratingKey: ratingKey,
                    type: type,
                    shouldResumeFromOffset: shouldResumeFromOffset,
                    shouldContinue: shouldContinue,
                )
            }
        #endif
        do {
            // A fresh lookup: the title's current rating decides, not the one a screen showed earlier.
            let media = try await services.detail.mediaItem(id: ratingKey)
            guard gate.isAllowed(media) else { return .blocked }
            let queue = try await services.playback.queue(
                startingWith: ratingKey,
                kind: type,
                shuffle: shuffle,
            )
            return present(
                queue,
                shouldResumeFromOffset: shouldResumeFromOffset,
                shouldContinue: shouldContinue,
            )
        } catch {
            return result(for: error)
        }
    }

    /// Plays the playlist in its order from `entry`, the entries before it staying in the queue.
    @discardableResult
    func playPlaylist(
        id: String,
        startingWith entry: PlaylistEntry,
        shouldContinue: @escaping @MainActor () -> Bool = { true },
    ) async -> Result {
        ThemeMusicPlayer.shared.silence()
        // Only a playable title can start a playlist; a nested collection or playlist never does.
        guard let entryMedia = entry.media.playableItem else { return .failed }
        guard gate.isAllowed(entryMedia) else { return .blocked }
        #if !os(tvOS)
            if offline.isUnreachable(services.identity) {
                return playDownloadedChecked(
                    ratingKey: entryMedia.id,
                    type: entryMedia.type,
                    shouldResumeFromOffset: true,
                    shouldContinue: shouldContinue,
                )
            }
        #endif
        do {
            let media = try await services.detail.mediaItem(id: entryMedia.id)
            guard gate.isAllowed(media) else { return .blocked }
            let queue = try await services.playback.queue(playlistID: id, startingWith: entry)
            return present(queue, shouldResumeFromOffset: true, shouldContinue: shouldContinue)
        } catch {
            return result(for: error)
        }
    }

    #if !os(tvOS)
        /// Plays the downloaded file of a movie or episode, or the next downloaded episode of a series or season.
        /// Only the active profile's downloads that the policy allows are played.
        @discardableResult
        func playDownloaded(ratingKey: String, type: MediaKind, shouldResumeFromOffset: Bool = true) -> Bool {
            playDownloadedChecked(
                ratingKey: ratingKey,
                type: type,
                shouldResumeFromOffset: shouldResumeFromOffset,
                shouldContinue: { true },
            ) == .started
        }

        private func playDownloadedChecked(
            ratingKey: String,
            type: MediaKind,
            shouldResumeFromOffset: Bool,
            shouldContinue: @MainActor () -> Bool,
        ) -> Result {
            guard let downloaded = offline.downloadedPlayback(
                for: MediaIdentity(server: services.identity, itemID: ratingKey),
                kind: type,
                resumes: shouldResumeFromOffset,
            ) else { return .failed }
            let request = downloaded.request
            let download = downloaded.download
            // The request must play this completed download of this server.
            guard download.status == .completed,
                  download.identity?.server == services.identity,
                  download.itemID == request.media.id
            else { return .failed }
            // The downloads grid's own rule: owned by the active profile, and both the metadata stored with the
            // download and the server metadata pinned for it pass the gate. Then the media the request plays.
            let access = DownloadAccessPolicy(
                activeOwnerIDs: offline.activeOwnerIDs,
                gate: gate,
                pinnedMedia: { [offline] item in offline.pinnedMedia(for: item) },
            )
            guard access.decision(for: download) == .allowed, gate.isAllowed(request.media) else { return .blocked }
            guard !Task.isCancelled, shouldContinue() else { return .failed }
            coordinator.showLocalPlayer(request)
            return .started
        }

        /// The same launcher, reading downloads and server reachability from `source`.
        func using(offline source: any OfflinePlaybackSource) -> PlaybackLauncher {
            var launcher = self
            launcher.offline = source
            return launcher
        }
    #endif

    func using(services: MediaServices) -> PlaybackLauncher {
        var launcher = PlaybackLauncher(
            services: services,
            coordinator: coordinator,
            gate: gate,
        )
        #if !os(tvOS)
            launcher.offline = offline
        #endif
        return launcher
    }

    // MARK: - Private

    private func present(
        _ queue: PlaybackQueue,
        shouldResumeFromOffset: Bool,
        shouldContinue: @MainActor () -> Bool,
    ) -> Result {
        guard !queue.items.isEmpty, queue.items.indices.contains(queue.currentIndex) else {
            return .failed
        }
        // Every member, not only the first: autoplay and the queue panel can reach any of them.
        guard queue.items.allSatisfy({ gate.isAllowed($0.media) }) else {
            return .blocked
        }
        guard !Task.isCancelled, shouldContinue() else {
            return .failed
        }
        coordinator.showPlayer(
            for: queue,
            services: services,
            shouldResumeFromOffset: shouldResumeFromOffset,
            notice: nil,
        )
        return .started
    }

    private func result(for error: Error) -> Result {
        if let safetyError = error as? ContentSafetyError {
            return safetyError == .blocked ? .blocked : .failed
        }
        guard !Task.isCancelled, !error.isCancellation else {
            return .failed
        }
        ErrorReporter.capture(error)
        return .failed
    }
}
