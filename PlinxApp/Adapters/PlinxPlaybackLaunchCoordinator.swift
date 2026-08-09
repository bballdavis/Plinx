import Combine
import Foundation

/// Owns the user-visible phase between a playback tap and a ready play queue.
///
/// Playback preparation is intentionally serialized here. A slow network must
/// never turn repeated taps into multiple queue-building requests.
@MainActor
final class PlaybackLaunchCoordinator: ObservableObject {
    struct PendingLaunch: Identifiable, Equatable {
        let id: UUID
    }

    @Published private(set) var pendingLaunch: PendingLaunch?
    @Published private(set) var lastResult: PlaybackLauncher.Result?

    private var launchTask: Task<Void, Never>?

    var isLaunching: Bool {
        pendingLaunch != nil
    }

    func launch(
        operation: @escaping @MainActor () async -> PlaybackLauncher.Result
    ) {
        guard pendingLaunch == nil else { return }

        let launchID = UUID()
        pendingLaunch = PendingLaunch(id: launchID)
        lastResult = nil

        launchTask = Task { @MainActor [weak self] in
            let result = await operation()

            guard !Task.isCancelled,
                  let self,
                  self.pendingLaunch?.id == launchID else {
                return
            }

            self.pendingLaunch = nil
            self.launchTask = nil
            self.lastResult = result
        }
    }

    func cancelPendingLaunch() {
        launchTask?.cancel()
        launchTask = nil
        pendingLaunch = nil
    }
}
