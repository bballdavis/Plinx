import Foundation
import Observation
import SwiftUI

/// Shared optimistic watched state for every Plinx presentation surface.
///
/// The store intentionally holds no media collection. Server-backed view models
/// remain the source of truth; a successful override bridges their reload lag
/// and a failed mutation restores the exact value that preceded the action.
/// Overrides are keyed by `MediaIdentity`, so equal item IDs on different
/// servers never share a state.
@MainActor
@Observable
final class PlinxWatchStatusStore {
    private(set) var overrides: [MediaIdentity: Bool] = [:]
    private(set) var inFlightIDs: Set<MediaIdentity> = []
    private var generation = 0

    /// Drops optimistic state when the active profile or its servers change.
    /// Generation checks keep an older request from clearing or rolling back a
    /// newer session's mutation for the same media identity.
    func reset() {
        generation &+= 1
        overrides.removeAll()
        inFlightIDs.removeAll()
    }

    func isWatched(_ item: MediaItem) -> Bool {
        if let override = overrides[item.identity] {
            return override
        }
        guard PlayableItemType(mediaKind: item.type) != nil else {
            return false
        }
        return item.isFullyWatched
    }

    func isWatched(_ item: MediaDisplayItem) -> Bool {
        guard let item = item.playableItem else { return false }
        return isWatched(item)
    }

    /// Performs one optimistic mutation per media identity. Returns `false`
    /// when a duplicate action is already in progress, so repeated remote
    /// activation cannot reverse the state before the first request completes.
    /// `services` must be the services of the item's own server.
    @discardableResult
    func toggle(
        _ item: MediaItem,
        services: MediaServices,
        isAllowed: Bool
    ) async throws -> Bool {
        guard isAllowed else { throw PlinxWatchStatusStoreError.notAllowed }
        guard services.identity == item.identity.server else {
            throw PlinxWatchStatusStoreError.serverUnavailable
        }
        let identity = item.identity
        guard !inFlightIDs.contains(identity) else { return false }

        let requestGeneration = generation
        let previousOverride = overrides[identity]
        let wasWatched = isWatched(item)
        inFlightIDs.insert(identity)
        overrides[identity] = !wasWatched

        defer {
            if generation == requestGeneration {
                inFlightIDs.remove(identity)
            }
        }

        do {
            try await services.detail.setPlayed(!wasWatched, itemID: item.id)
            guard generation == requestGeneration else { return false }
            // Screens that list this server (home rows, Continue Watching)
            // reload through the server's watch-state revision.
            services.noteWatchStateChanged()
            return true
        } catch {
            guard generation == requestGeneration else { return false }
            if let previousOverride {
                overrides[identity] = previousOverride
            } else {
                overrides.removeValue(forKey: identity)
            }
            throw error
        }
    }
}

enum PlinxWatchStatusStoreError: LocalizedError {
    case notAllowed
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            String(localized: "media.unavailable.title", table: "Plinx")
        case .serverUnavailable:
            String(localized: "server.unavailable.title")
        }
    }
}

extension EnvironmentValues {
    /// Optimistic watched-state overrides published by `PlinxWatchStatusStore`,
    /// keyed by media identity. Watched badges read it so a successful toggle
    /// shows before the owning view model reloads.
    @Entry var watchedOverrides: [MediaIdentity: Bool] = [:]
}
