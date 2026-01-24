import Foundation

public final class PlaybackCoordinator: ObservableObject {
    public enum State: Sendable, Equatable {
        case stopped
        case playing(id: String)
        case paused(id: String)
    }

    @Published public private(set) var state: State = .stopped
    private let policy: PlaybackPolicy

    public init(policy: PlaybackPolicy = PlaybackPolicy()) {
        self.policy = policy
    }

    public func play(id: String) {
        state = .playing(id: id)
    }

    public func pause(id: String) {
        state = .paused(id: id)
    }

    public func stop() {
        state = .stopped
    }

    public func handleBackgrounding() {
        guard policy.shouldStopOnBackground() else { return }
        stop()
        if policy.shouldClearSensitiveStateOnBackground() {
            // Placeholder: clear caches or sensitive playback state if needed
        }
    }
}
