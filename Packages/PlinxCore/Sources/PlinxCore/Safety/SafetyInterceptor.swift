public struct SafetyInterceptor: Sendable {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy = SafetyPolicy()) {
        self.policy = policy
    }

    public func isAllowed(_ item: PlinxMediaItem) -> Bool {
        // Label check
        switch policy.labelMatchMode {
        case .required(let label):
            guard item.labels.contains(label) else { return false }
        case .any(let labels):
            guard labels.isEmpty || item.labels.contains(where: { labels.contains($0) }) else { return false }
        case .all(let labels):
            guard labels.allSatisfy({ item.labels.contains($0) }) else { return false }
        case .none:
            break // library-level gating is in effect; skip item-label check
        }

        // Rating check — fail-closed: unrecognised or absent rating → reject
        guard let rating = item.rating else { return false }
        return rating <= policy.maxRating
    }

    public func filter(_ items: [PlinxMediaItem]) -> [PlinxMediaItem] {
        items.filter(isAllowed)
    }
}
