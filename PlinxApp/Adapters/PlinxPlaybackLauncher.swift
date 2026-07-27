import Foundation
import PlinxCore

/// Final playback authorization boundary for Plinx.
///
/// Navigation decorators keep unsafe content out of the UI, while this launcher
/// re-fetches the selected item and validates every queue member immediately
/// before presenting the player. Missing metadata and request failures reject
/// playback.
@MainActor
struct PlaybackLauncher {
    let context: PlexAPIContext
    let coordinator: any PlaybackPresenting
    let safetyPolicy: SafetyPolicy

    func play(
        ratingKey: String,
        type: PlexItemType,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true,
    ) async {
        do {
            guard try await isAllowed(ratingKey: ratingKey) else { return }

            let manager = try PlayQueueManager(context: context)
            let continuous = type == .episode || type == .show || type == .season
            var playQueue = try await manager.createQueue(
                for: ratingKey,
                itemType: type,
                continuous: continuous,
                shuffle: shuffle,
            )

            if try await isAllowed(playQueue: playQueue) == false, continuous {
                playQueue = try await manager.createQueue(
                    for: ratingKey,
                    itemType: type,
                    continuous: false,
                    shuffle: false,
                )
            }

            guard playQueue.selectedRatingKey != nil,
                  try await isAllowed(playQueue: playQueue)
            else { return }

            coordinator.showPlayer(
                for: playQueue,
                shouldResumeFromOffset: shouldResumeFromOffset,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    private func isAllowed(ratingKey: String) async throws -> Bool {
        let repository = try MetadataRepository(context: context)
        let response = try await repository.getMetadata(ratingKey: ratingKey)
        guard let item = response.mediaContainer.metadata?.first else {
            return false
        }
        return StrimrAdapter.isAllowed(
            MediaItem(plexItem: item),
            policy: safetyPolicy,
        )
    }

    private func isAllowed(playQueue: PlayQueueState) async throws -> Bool {
        for item in playQueue.items {
            guard try await isAllowed(ratingKey: item.ratingKey) else {
                return false
            }
        }
        return true
    }
}
