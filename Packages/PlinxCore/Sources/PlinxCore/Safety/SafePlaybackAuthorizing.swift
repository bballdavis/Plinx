/// The public access decision used at display and playback boundaries.
public typealias ContentAccessDecision = FilterDecision

/// A small, injectable safety seam for playback launchers.
public protocol SafePlaybackAuthorizing: Sendable {
    func decision(for item: PlinxMediaItem) -> ContentAccessDecision
}

public struct PolicyPlaybackAuthorizer: SafePlaybackAuthorizing, Sendable {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func decision(for item: PlinxMediaItem) -> ContentAccessDecision {
        SafetyInterceptor(policy: policy).explain(item)
    }
}
