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
}
