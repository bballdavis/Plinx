public struct SafetyInterceptor: Sendable {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy = SafetyPolicy()) {
        self.policy = policy
    }

    public func isAllowed(_ item: PlinxMediaItem) -> Bool {
        guard item.labels.contains(policy.requiredLabel) else {
            return false
        }

        if let rating = item.rating {
            return rating <= policy.maxRating
        }

        return false
    }

    public func filter(_ items: [PlinxMediaItem]) -> [PlinxMediaItem] {
        items.filter(isAllowed)
    }
}
