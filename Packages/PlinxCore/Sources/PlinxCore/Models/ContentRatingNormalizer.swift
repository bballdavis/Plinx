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
// note after the rating ("PG-13 (US)", "PG 13 (US)", "R for violence").
//
// Everything else is `.unrated`, which the safety policy rejects unless a
// parent opts in to unrated content. Ratings that are explicitly adult are
// `.adultOnly`: NC-17, X, and any age certificate of 18 or older from any
// country ("18", "R18+", "FSK 18", "KR-19", "R21", "21+", "18A", "18SX").
// They sit above every ceiling a parent can choose and are rejected even when
// unrated content is allowed.
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
    /// Rated for adults only (NC-17, X, an age certificate of 18 or older). Never allowed.
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
        // A note after the rating: "PG-13 (US)", "R for violence". The rating
        // itself may contain spaces ("PG 13 (US)", "R 21 (SG)", "NC 17 for
        // ..."), so the longest leading run of words that is a rating wins.
        // Taking only the first word would read those as PG, R, or unrated.
        let tokens = value.split(separator: " ")
        for count in stride(from: tokens.count - 1, through: 1, by: -1) {
            if let classification = match(compact(tokens[..<count].joined())) {
                return classification
            }
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
        if adultRatings.contains(key) || isAdultAgeCertificate(key) {
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

    /// An age certificate of 18 or older from any country or board: a two-digit age of at least
    /// 18 with an optional `+` on either side, any country, board or class letters before it, and
    /// an optional class suffix of up to two letters after it.
    ///
    /// "18", "18+", "+18", "19", "21+", "R18+", "R21", "M18", "GB18", "DE18", "FSK18", "DEFSK18",
    /// "KR19", "SGR21", "GERMANYFSK18", "18A", "18SX", "18SG". Ages under 18 ("12A", "MA15+",
    /// "NC16") are not adult. The letters before the age are not limited in length, because a
    /// spelled-out country ("South Korea:19") must not turn an adult rating into an unrated one.
    private static func isAdultAgeCertificate(_ key: String) -> Bool {
        var body = Substring(key)
        if body.hasPrefix("+") { body = body.dropFirst() }
        if body.hasSuffix("+") { body = body.dropLast() }
        let prefix = body.prefix(while: isASCIILetter)
        let rest = body.dropFirst(prefix.count)
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        let suffix = rest.dropFirst(digits.count)
        guard digits.count == 2,
              suffix.count <= 2,
              suffix.allSatisfy(isASCIILetter),
              let age = Int(digits)
        else { return false }
        return age >= 18
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
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
