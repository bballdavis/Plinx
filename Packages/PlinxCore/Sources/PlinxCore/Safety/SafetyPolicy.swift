/// Controls how item labels are matched during safety filtering.
public enum LabelMatchMode: Sendable, Equatable {
    /// Item must contain this single label (original / default behavior).
    case required(String)
    /// Item must contain at least one of the given labels.
    case any([String])
    /// Item must contain every one of the given labels.
    case all([String])
    /// No label requirement — rely on library-level gating + rating check only.
    case none
}

public struct SafetyPolicy: Sendable, Equatable {
    public let labelMatchMode: LabelMatchMode
    public let maxRating: PlinxRating

    /// Legacy init preserving the original `requiredLabel` parameter name.
    public init(requiredLabel: String = "Kids", maxRating: PlinxRating = .g) {
        self.labelMatchMode = .required(requiredLabel)
        self.maxRating = maxRating
    }

    /// Full init with explicit label match mode (use `.none` for Strimr adapters
    /// that apply library-level gating instead of item-level label checks).
    public init(labelMatchMode: LabelMatchMode, maxRating: PlinxRating) {
        self.labelMatchMode = labelMatchMode
        self.maxRating = maxRating
    }

    /// Convenience for Strimr adapter path: rating-only, no label requirement.
    public static func ratingOnly(max: PlinxRating = .g) -> SafetyPolicy {
        SafetyPolicy(labelMatchMode: .none, maxRating: max)
    }

    // Backward-compatible accessor for code that reads the single required label.
    public var requiredLabel: String {
        guard case .required(let label) = labelMatchMode else { return "" }
        return label
    }
}
