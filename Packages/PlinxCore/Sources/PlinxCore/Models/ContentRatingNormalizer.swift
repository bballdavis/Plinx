// ─────────────────────────────────────────────────────────────────────────────
// ContentRatingNormalizer — raw server rating text → PlinxRating
// ─────────────────────────────────────────────────────────────────────────────
//
// Plex reports a title's rating in `contentRating` and Jellyfin in
// `OfficialRating`. Both are free text. This normalizer accepts only the US
// systems Plinx's ceilings are expressed in:
//
//   • MPAA movie ratings: G, PG, PG-13, R
//   • US TV Parental Guidelines: TV-Y, TV-Y7, TV-G, TV-PG, TV-14, TV-MA, with
//     optional content descriptors (D, L, S, V, FV), e.g. "TV-Y7-FV", "TV-14-LV"
//
// in the spellings the servers produce: any case, `_` or spaces for `-`, a
// `US-`/`US:`/`US/`/`US ` country prefix, a `Rated ` prefix, and a trailing
// note after the rating ("PG-13 (US)", "R for violence").
//
// Everything else is `.unrated`, which the safety policy rejects unless a
// parent opts in to unrated content. Ratings that are explicitly adult (NC-17,
// X, or an 18 certificate from any country) are `.adultOnly`: they sit above
// every ceiling a parent can choose and are rejected even when unrated content
// is allowed.
//
// Other national systems are deliberately not mapped onto US ratings. Add one
// only with tests and a parent-visible mapping.
//
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

/// What a raw rating string means for the safety policy.
public enum ContentRatingClassification: Sendable, Equatable {
    /// A recognized US movie or TV rating.
    case rated(PlinxRating)
    /// Rated for adults only (NC-17, X, an 18 certificate). Never allowed.
    case adultOnly
    /// Missing, explicitly not rated, or a rating system Plinx does not map.
    /// Allowed only when the policy allows unrated content.
    case unrated
}

public enum ContentRatingNormalizer {
    /// Classifies a raw `contentRating` / `OfficialRating` value. Deterministic and side-effect free.
    public static func classify(_ raw: String?) -> ContentRatingClassification {
        guard let raw else { return .unrated }
        var value = raw
            .replacingOccurrences(of: "_", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .uppercased()
        value = removingRatedPrefix(value)
        if let remainder = removingUSPrefix(value) {
            value = removingRatedPrefix(remainder)
        }
        guard !value.isEmpty else { return .unrated }

        if let classification = match(compact(value)) {
            return classification
        }
        // A note after the rating: "PG-13 (US)", "R for violence".
        let tokens = value.split(separator: " ")
        if tokens.count > 1, let classification = match(compact(String(tokens[0]))) {
            return classification
        }
        return .unrated
    }

    // MARK: - Matching

    private static let movieRatings: [String: PlinxRating] = [
        "G": .g,
        "PG": .pg,
        "PG13": .pg13,
        "R": .r,
    ]

    /// Longest base first, so "Y7" wins over "Y".
    private static let tvBases: [(String, PlinxRating)] = [
        ("Y7", .tvY7),
        ("Y", .tvY),
        ("PG", .tvPg),
        ("14", .tv14),
        ("MA", .tvMa),
        ("G", .tvG),
    ]

    private static let adultRatings: Set<String> = ["NC17", "X", "XX", "XXX"]

    private static func match(_ key: String) -> ContentRatingClassification? {
        guard !key.isEmpty else { return nil }
        if let rating = movieRatings[key] {
            return .rated(rating)
        }
        if adultRatings.contains(key) || isEighteenCertificate(key) {
            return .adultOnly
        }
        if let rating = tvRating(key) {
            return .rated(rating)
        }
        return nil
    }

    /// "TVY7FV" → TV-Y7. The part after the base may only hold content descriptors.
    private static func tvRating(_ key: String) -> PlinxRating? {
        guard key.hasPrefix("TV") else { return nil }
        let rest = key.dropFirst(2)
        for (base, rating) in tvBases where rest.hasPrefix(base) {
            let descriptors = rest.dropFirst(base.count).replacingOccurrences(of: "FV", with: "")
            return descriptors.allSatisfy { "DLSV".contains($0) } ? rating : nil
        }
        return nil
    }

    /// "18", "18+", "R18", "R18+", or a short country/board code before 18 ("GB18", "DE18", "FSK18").
    private static func isEighteenCertificate(_ key: String) -> Bool {
        var body = Substring(key)
        if body.hasSuffix("+") {
            body = body.dropLast()
        }
        guard body.hasSuffix("18") else { return false }
        let prefix = body.dropLast(2)
        return prefix.count <= 4 && prefix.allSatisfy { $0.isASCII && $0.isLetter }
    }

    // MARK: - Spelling

    /// Drops separators so "PG-13", "PG 13" and "(PG13)" compare equal.
    private static func compact(_ value: String) -> String {
        String(value.filter { !" -:/().".contains($0) })
    }

    /// "RATED PG-13", "RATED: R" → the rating.
    private static func removingRatedPrefix(_ value: String) -> String {
        guard value.hasPrefix("RATED") else { return value }
        let rest = value.dropFirst("RATED".count)
        guard let first = rest.first, " :-".contains(first) else { return value }
        return String(rest.drop { " :-".contains($0) })
    }

    /// "US-PG", "US:TV-14", "US/R", "US PG" → the rating; nil without a US prefix.
    private static func removingUSPrefix(_ value: String) -> String? {
        guard value.hasPrefix("US") else { return nil }
        let rest = value.dropFirst(2)
        guard let separator = rest.first, " -:/".contains(separator) else { return nil }
        let remainder = rest.drop { " -:/".contains($0) }
        return remainder.isEmpty ? nil : String(remainder)
    }
}
