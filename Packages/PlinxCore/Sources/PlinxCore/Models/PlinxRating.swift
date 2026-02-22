public enum PlinxRating: String, CaseIterable, Comparable, Sendable {
    case tvY = "TV-Y"
    case g = "G"
    case tvY7 = "TV-Y7"
    case pg = "PG"
    case tvPg = "TV-PG"
    case pg13 = "PG-13"
    case tv14 = "TV-14"
    case r = "R"
    case tvMa = "TV-MA"

    public static func < (lhs: PlinxRating, rhs: PlinxRating) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .tvY: return 0
        case .g: return 1
        case .tvY7: return 2
        case .pg: return 3
        case .tvPg: return 4
        case .pg13: return 5
        case .tv14: return 6
        case .r: return 7
        case .tvMa: return 8
        }
    }

    /// `true` for TV-style ratings (TV-Y, TV-Y7, TV-PG, TV-14, TV-MA).
    public var isTVRating: Bool {
        rawValue.hasPrefix("TV-")
    }

    /// `true` for MPAA movie ratings (G, PG, PG-13, R).
    public var isMovieRating: Bool {
        !isTVRating
    }

    /// All TV-style ratings in ascending severity order.
    public static var tvRatings: [PlinxRating] {
        allCases.filter(\.isTVRating)
    }

    /// All MPAA movie ratings in ascending severity order.
    public static var movieRatings: [PlinxRating] {
        allCases.filter(\.isMovieRating)
    }

    /// Parses Plex/content-rating text into a known `PlinxRating`.
    /// Normalizes casing/spacing and accepts common TV aliases.
    public static func from(contentRating raw: String?) -> PlinxRating? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "TVY", "TV-Y": return .tvY
        case "TVY7", "TV-Y7": return .tvY7
        case "TVPG", "TV-PG": return .tvPg
        case "TV14", "TV-14": return .tv14
        case "TVMA", "TV-MA": return .tvMa
        case "G": return .g
        case "PG": return .pg
        case "PG13", "PG-13": return .pg13
        case "R": return .r
        default: return nil
        }
    }
}
