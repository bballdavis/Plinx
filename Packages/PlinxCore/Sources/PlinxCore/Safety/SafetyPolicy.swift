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

    /// Full init with explicit label match mode.
    public init(
        labelMatchMode: LabelMatchMode,
        maxMovieRating: PlinxRating,
        maxTVRating: PlinxRating,
        allowUnrated: Bool = false
    ) {
        self.labelMatchMode = labelMatchMode
        self.maxMovieRating = maxMovieRating
        self.maxTVRating = maxTVRating
        self.allowUnrated = allowUnrated
    }

    /// Convenience: the default parent-managed rating policy.
    /// Movies default to G and television defaults to TV-Y.
    public static func ratingOnly(allowUnrated: Bool = false) -> SafetyPolicy {
        SafetyPolicy(
            labelMatchMode: .none,
            maxMovieRating: .g,
            maxTVRating: .tvY,
            allowUnrated: allowUnrated
        )
    }

    /// Convenience: rating-only, no label requirement, with one ceiling for
    /// both movie and TV content.
    public static func ratingOnly(
        max: PlinxRating,
        allowUnrated: Bool = false
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
        allowUnrated: Bool = false
    ) -> SafetyPolicy {
        SafetyPolicy(
            labelMatchMode: .none,
            maxMovieRating: maxMovie,
            maxTVRating: maxTV,
            allowUnrated: allowUnrated
        )
    }

}
