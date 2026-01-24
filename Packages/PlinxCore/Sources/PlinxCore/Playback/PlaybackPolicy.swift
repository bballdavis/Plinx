public struct PlaybackPolicy: Sendable {
    public init() {}

    public func shouldStopOnBackground() -> Bool { true }
    public func shouldClearSensitiveStateOnBackground() -> Bool { true }
}
