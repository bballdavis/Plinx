import Foundation
import Observation

/// Shared optimistic watched state for every Plinx presentation surface.
///
/// The store intentionally holds no media collection. Server-backed view models
/// remain the source of truth; a successful override bridges their reload lag
/// and a failed mutation restores the exact value that preceded the action.
@MainActor
@Observable
final class PlinxWatchStatusStore {
    private(set) var overrides: [String: Bool] = [:]
    private(set) var inFlightIDs: Set<String> = []
    private var generation = 0

    /// Drops optimistic state when the active server or profile changes.
    /// Generation checks keep an older request from clearing or rolling back a
    /// newer session's mutation for the same media identifier.
    func reset() {
        generation &+= 1
        overrides.removeAll()
        inFlightIDs.removeAll()
    }

    func isWatched(_ item: MediaItem) -> Bool {
        if let override = overrides[item.id] {
            return override
        }

        guard let playableType = PlayableItemType(plexType: item.type) else {
            return false
        }

        switch playableType {
        case .movie, .episode, .clip:
            return (item.viewCount ?? 0) > 0
        case .show, .season:
            guard let leafCount = item.leafCount,
                  let viewedLeafCount = item.viewedLeafCount,
                  leafCount > 0
            else {
                return false
            }
            return leafCount == viewedLeafCount
        }
    }

    func isWatched(_ item: MediaDisplayItem) -> Bool {
        guard let item = item.playableItem else { return false }
        return isWatched(item)
    }

    /// Performs one optimistic mutation per media ID. Returns `false` when a
    /// duplicate action is already in progress, so repeated remote activation
    /// cannot reverse the state before the first request completes.
    @discardableResult
    func toggle(
        _ item: MediaItem,
        context: PlexAPIContext,
        isAllowed: Bool
    ) async throws -> Bool {
        guard isAllowed else { throw PlinxWatchStatusStoreError.notAllowed }
        guard !inFlightIDs.contains(item.id) else { return false }

        let requestGeneration = generation
        let previousOverride = overrides[item.id]
        let wasWatched = isWatched(item)
        inFlightIDs.insert(item.id)
        overrides[item.id] = !wasWatched

        defer {
            if generation == requestGeneration {
                inFlightIDs.remove(item.id)
            }
        }

        do {
            let repository = try ScrobbleRepository(context: context)
            if wasWatched {
                try await repository.markUnwatched(key: item.id)
            } else {
                try await repository.markWatched(key: item.id)
            }
            guard generation == requestGeneration else { return false }
            return true
        } catch {
            guard generation == requestGeneration else { return false }
            overrides[item.id] = previousOverride
            if previousOverride == nil {
                overrides.removeValue(forKey: item.id)
            }
            throw error
        }
    }
}

enum PlinxWatchStatusStoreError: LocalizedError {
    case notAllowed

    var errorDescription: String? {
        String(localized: "media.unavailable.title", table: "Plinx")
    }
}
