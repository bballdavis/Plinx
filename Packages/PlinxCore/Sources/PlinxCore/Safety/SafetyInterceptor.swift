// ─────────────────────────────────────────────────────────────────────────────
// SafetyInterceptor — Fail-Closed Content Filter
// ─────────────────────────────────────────────────────────────────────────────
//
// The SafetyInterceptor is the single choke-point through which ALL media
// content must pass before it reaches any Plinx view. It enforces two gates:
//
//   1. **Label gate** — items must carry the required label(s) (e.g. "Kids").
//      Configurable via `LabelMatchMode` (required, any, all, none).
//
//   2. **Rating gate** — items must have a recognized content rating that does
//      not exceed the policy maximum. Missing or unrecognized ratings are
//      REJECTED (fail-closed).
//
// Design Principles:
//   • Fail-closed: when in doubt, reject. No content is "safe by default".
//   • Deterministic: given the same policy + item, the result is always the same.
//   • Sendable: safe to use from any actor/thread.
//   • No side effects: pure filtering, no logging or analytics.
//
// ─────────────────────────────────────────────────────────────────────────────

/// Filters media content according to a `SafetyPolicy`.
///
/// Usage:
/// ```swift
/// let interceptor = SafetyInterceptor(policy: .ratingOnly(max: .pg))
/// let safe = interceptor.filter(allItems)  // only G and PG survive
/// ```
public struct SafetyInterceptor: Sendable {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy = SafetyPolicy()) {
        self.policy = policy
    }

    // MARK: - Single Item

    /// Returns `true` if the item passes both the label gate and the rating gate.
    ///
    /// **Fail-closed behavior:**
    /// - Missing rating → rejected
    /// - Unrecognized rating string (not in `PlinxRating`) → rejected
    /// - Missing labels when label matching is active → rejected
    public func isAllowed(_ item: PlinxMediaItem) -> Bool {
        guard passesLabelGate(item) else { return false }
        guard passesRatingGate(item) else { return false }
        return true
    }

    // MARK: - Batch Filtering

    /// Filters an array, keeping only items that pass both gates.
    public func filter(_ items: [PlinxMediaItem]) -> [PlinxMediaItem] {
        items.filter(isAllowed)
    }

    /// Filters a hub (titled group of items). Returns `nil` if no items survive,
    /// effectively removing empty hubs from the UI.
    public func filterHub(_ hub: PlinxHub) -> PlinxHub? {
        let allowed = hub.items.filter(isAllowed)
        guard !allowed.isEmpty else { return nil }
        return PlinxHub(id: hub.id, title: hub.title, items: allowed)
    }

    /// Filters an array of hubs, removing any that become empty after filtering.
    public func filterHubs(_ hubs: [PlinxHub]) -> [PlinxHub] {
        hubs.compactMap(filterHub)
    }

    // MARK: - Decision Explanation (for debugging / audit trail)

    /// Returns a human-readable explanation of why an item was allowed or rejected.
    /// Useful for development-time debugging — never shown to children.
    public func explain(_ item: PlinxMediaItem) -> FilterDecision {
        if !passesLabelGate(item) {
            return .rejected(reason: .labelMismatch(
                required: policy.labelMatchMode,
                actual: item.labels
            ))
        }
        guard let rating = item.rating else {
            return policy.allowUnrated ? .allowed : .rejected(reason: .missingRating)
        }
        let maxAllowed = rating.isTVRating ? policy.maxTVRating : policy.maxMovieRating
        if rating > maxAllowed {
            return .rejected(reason: .ratingExceedsMax(
                itemRating: rating,
                maxAllowed: maxAllowed
            ))
        }
        return .allowed
    }

    // MARK: - Private Gates

    private func passesLabelGate(_ item: PlinxMediaItem) -> Bool {
        switch policy.labelMatchMode {
        case .required(let label):
            return item.labels.contains(label)
        case .any(let labels):
            // Empty label set = no label requirement (pass-through)
            return labels.isEmpty || item.labels.contains(where: { labels.contains($0) })
        case .all(let labels):
            return labels.allSatisfy({ item.labels.contains($0) })
        case .none:
            // Library-level gating is in effect; skip item-label check
            return true
        }
    }

    private func passesRatingGate(_ item: PlinxMediaItem) -> Bool {
        guard let rating = item.rating else {
            return policy.allowUnrated
        }
        let maxAllowed = rating.isTVRating ? policy.maxTVRating : policy.maxMovieRating
        return rating <= maxAllowed
    }
}

// MARK: - Filter Decision

/// A transparent explanation of a filtering decision.
public enum FilterDecision: Sendable, Equatable {
    case allowed
    case rejected(reason: RejectionReason)

    public enum RejectionReason: Sendable, Equatable {
        /// Item lacks the required label(s).
        case labelMismatch(required: LabelMatchMode, actual: [String])
        /// Item has no content rating (fail-closed).
        case missingRating
        /// Item's rating exceeds the policy maximum.
        case ratingExceedsMax(itemRating: PlinxRating, maxAllowed: PlinxRating)
    }
}

// MARK: - PlinxHub (public bridge type for Hub filtering)

/// A lightweight public representation of a content hub (titled group of items).
/// Used by SafetyInterceptor's hub-filtering methods and by PlinxUI views.
public struct PlinxHub: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let items: [PlinxMediaItem]

    public var hasItems: Bool { !items.isEmpty }

    public init(id: String, title: String, items: [PlinxMediaItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}
