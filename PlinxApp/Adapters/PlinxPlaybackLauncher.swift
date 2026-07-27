import Foundation
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// PlinxPlaybackLauncher — Safety-enforcing replacement for Strimr's launcher
//
// Fetches current metadata immediately before playback, rejects unsafe queue
// members, and keeps playback inside Plinx's MPV path so content authorization
// and Maximum Playback Level cannot be bypassed by an external player.
//
// When Strimr fixes this upstream, delete this file and remove the exclude
// from project.yml.
// ─────────────────────────────────────────────────────────────────────────────

struct PlaybackLauncher {
    enum Result: Equatable {
        case started
        case blocked
        case failed
    }

    let context: PlexAPIContext
    let coordinator: MainCoordinator
    let safetyPolicy: SafetyPolicy

    @MainActor
    func play(
        ratingKey: String,
        type: PlexItemType,
        shouldResumeFromOffset: Bool = true
    ) async -> Result {
        do {
            let authorizer = PlexSafetyPlaybackAuthorizer(context: context, policy: safetyPolicy)
            guard await authorizer.decision(
                ratingKey: ratingKey
            ) == .allowed else {
                return .blocked
            }

            let manager = try PlayQueueManager(context: context)
            var playQueue = try await manager.createQueue(
                for: ratingKey,
                itemType: type,
                continuous: type == .episode
            )

            if !authorizer.isAllowed(playQueue: playQueue) {
                playQueue = try await manager.createQueue(
                    for: ratingKey,
                    itemType: type,
                    continuous: false
                )
            }
            guard authorizer.isAllowed(playQueue: playQueue) else {
                return .blocked
            }

            guard playQueue.selectedRatingKey != nil else {
                return .failed
            }

            coordinator.showPlayer(for: playQueue, shouldResumeFromOffset: shouldResumeFromOffset)
            return .started
        } catch {
            debugPrint("Failed to create play queue:", error)
            ErrorReporter.capture(error)
            return .failed
        }
    }

}

private struct PlexSafetyPlaybackAuthorizer {
    let context: PlexAPIContext
    let policy: SafetyPolicy

    func decision(ratingKey: String) async -> ContentAccessDecision {
        do {
            let repository = try MetadataRepository(context: context)
            let response = try await repository.getMetadata(ratingKey: ratingKey)
            guard let item = response.mediaContainer.metadata?.first else {
                return .rejected(reason: .missingRating)
            }
            return StrimrAdapter.decision(MediaItem(plexItem: item), policy: policy)
        } catch {
            return .rejected(reason: .missingRating)
        }
    }

    func isAllowed(playQueue: PlayQueueState) -> Bool {
        guard !playQueue.items.isEmpty else { return false }
        return playQueue.items.allSatisfy {
            StrimrAdapter.isAllowed(MediaItem(plexItem: $0), policy: policy)
        }
    }
}
