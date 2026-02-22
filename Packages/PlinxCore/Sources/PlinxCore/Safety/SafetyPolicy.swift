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

    /// Maximum allowed rating for movie content (G, PG, PG-13, R).
    public let maxMovieRating: PlinxRating

    /// Maximum allowed rating for TV content (TV-Y, TV-Y7, TV-PG, TV-14, TV-MA).
    public let maxTVRating: PlinxRating

    /// When `true`, items with no `contentRating` are allowed through.
    /// Library-level gating is the primary guard for this path.
    public let allowUnrated: Bool

    // MARK: - Inits

    /// Legacy init — single rating applied to both movie and TV content.
    public init(requiredLabel: String = "Kids", maxRating: PlinxRating = .g) {
        self.labelMatchMode = .required(requiredLabel)
        self.maxMovieRating = maxRating
        self.maxTVRating = maxRating
        self.allowUnrated = true
    }

    /// Full init with explicit label match mode.
    public init(
        labelMatchMode: LabelMatchMode,
        maxMovieRating: PlinxRating,
        maxTVRating: PlinxRating,
        allowUnrated: Bool = true
    ) {
        self.labelMatchMode = labelMatchMode
        self.maxMovieRating = maxMovieRating
        self.maxTVRating = maxTVRating
        self.allowUnrated = allowUnrated
    }

    /// Convenience: rating-only, no label requirement.
    /// Uses a single rating for both movie and TV (backward-compatible).
    public static func ratingOnly(
        max: PlinxRating = .g,
        allowUnrated: Bool = true
    ) -> SafetyPolicy {
        SafetyPolicy(
            labelMatchMode: .none,
            maxMovieRating: max,
            maxTVRating: max,
            allowUnrated: allowUnrated
        )
    }

    /// Convenience: specify separate max ratings for movie and TV.
    public static func ratingOnly(
        maxMovie: PlinxRating,
        maxTV: PlinxRating,
        allowUnrated: Bool = true
    ) -> SafetyPolicy {
        SafetyPolicy(
            labelMatchMode: .none,
            maxMovieRating: maxMovie,
            maxTVRating: maxTV,
            allowUnrated: allowUnrated
        )
    }

    // MARK: - Backward-compat accessors

    /// Single unified max rating — returns the stricter of the two.
    public var maxRating: PlinxRating {
        min(maxMovieRating, maxTVRating)
    }

    /// Backward-compatible accessor for code that reads the required label.
    public var requiredLabel: String {
        guard case .required(let label) = labelMatchMode else { return "" }
        return label
    }
}
