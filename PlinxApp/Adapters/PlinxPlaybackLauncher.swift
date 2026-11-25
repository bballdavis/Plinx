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
// A downloaded copy plays only when it is the active profile's own and
// `DownloadAccessPolicy` allows it (stored and pinned metadata both pass).
//
// External players are never used: handing a title to another app bypasses
// the content checks and the volume cap (`allowsExternalPlayer` is accepted
// for source compatibility and ignored).
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

@MainActor
struct PlaybackLauncher {
    enum Result: Equatable {
        case started
        case blocked
        case failed
    }

    let services: MediaServices
    let coordinator: any PlaybackPresenting
    /// A policy captured by the caller, checked on top of the shared gate. Both must allow a title.
    let safetyPolicy: SafetyPolicy?
    let gate: ContentSafetyGate

    /// - Parameter gate: the shared gate when `nil` (resolved on the main actor, unlike a default argument).
    init(
        services: MediaServices,
        coordinator: any PlaybackPresenting,
        safetyPolicy: SafetyPolicy? = nil,
        gate: ContentSafetyGate? = nil,
    ) {
        self.services = services
        self.coordinator = coordinator
        self.safetyPolicy = safetyPolicy
        self.gate = gate ?? .shared
    }

    /// Plays a title, or the next episode of a series or season.
    /// - Parameters:
    ///   - allowsExternalPlayer: ignored; Plinx always uses its own player.
    ///   - shouldContinue: checked right before presenting, so a cancelled launch never opens the player.
    @discardableResult
    func play(
        ratingKey: String,
        type: MediaKind,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true,
        allowsExternalPlayer _: Bool = true,
        shouldContinue: @escaping @MainActor () -> Bool = { true },
    ) async -> Result {
        ThemeMusicPlayer.shared.silence()
        #if !os(tvOS)
            // Without the server, the downloaded copy is played instead of streaming.
            if !shuffle, OfflineCoordinator.shared.isUnreachable(services.identity) {
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
            guard isAllowed(media) else { return .blocked }
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
        guard isAllowed(entryMedia) else { return .blocked }
        #if !os(tvOS)
            if OfflineCoordinator.shared.isUnreachable(services.identity) {
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
            guard isAllowed(media) else { return .blocked }
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
            // `localPlaybackRequest(for:kind:)` only picks among the active profile's own completed downloads.
            guard let downloads = DownloadManager.shared,
                  let request = downloads.localPlaybackRequest(
                      for: MediaIdentity(server: services.identity, itemID: ratingKey),
                      kind: type,
                      resumes: shouldResumeFromOffset,
                  ),
                  let download = downloads.ownedItems.first(where: {
                      $0.status == .completed
                          && $0.identity?.server == services.identity
                          && $0.itemID == request.media.id
                  })
            else { return .failed }
            // The downloads grid's own rule: owned by the active profile, and both the metadata stored with the
            // download and the server metadata pinned for it pass the gate. Then the caller's policy, if any.
            guard DownloadAccessPolicy(downloadManager: downloads, gate: gate).decision(for: download) == .allowed,
                  isAllowed(request.media)
            else { return .blocked }
            guard !Task.isCancelled, shouldContinue() else { return .failed }
            coordinator.showLocalPlayer(request)
            return .started
        }
    #endif

    func using(services: MediaServices) -> PlaybackLauncher {
        PlaybackLauncher(
            services: services,
            coordinator: coordinator,
            safetyPolicy: safetyPolicy,
            gate: gate,
        )
    }

    /// Both the shared gate and the caller's policy, when it gave one, must allow the title.
    func isAllowed(_ media: MediaItem) -> Bool {
        guard gate.isAllowed(media) else { return false }
        guard let safetyPolicy else { return true }
        return PlinxContentRules.isAllowed(media, policy: safetyPolicy)
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
        guard queue.items.allSatisfy({ isAllowed($0.media) }) else {
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
