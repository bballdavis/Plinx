// ─────────────────────────────────────────────────────────────────────────────
// ContentRatingNormalizerTests.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// The normalizer is the only place raw Plex `contentRating` and Jellyfin
// `OfficialRating` text becomes a PlinxRating. It must accept the US forms the
// servers produce and classify everything else as unrated (fail closed) or
// adult-only (never allowed).
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(Testing)
import Testing
@testable import PlinxCore

private let canonicalRatings: [(String, PlinxRating)] = [
    ("G", .g),
    ("PG", .pg),
    ("PG-13", .pg13),
    ("R", .r),
    ("TV-Y", .tvY),
    ("TV-Y7", .tvY7),
    ("TV-G", .tvG),
    ("TV-PG", .tvPg),
    ("TV-14", .tv14),
    ("TV-MA", .tvMa),
]

private let serverSpellings: [(String, PlinxRating)] = [
    // Case, spacing and delimiter variants
    ("pg-13", .pg13),
    ("Pg 13", .pg13),
    ("PG13", .pg13),
    ("PG_13", .pg13),
    ("  tv-ma ", .tvMa),
    ("TV PG", .tvPg),
    ("TVPG", .tvPg),
    ("TV_Y7", .tvY7),
    ("tv-y", .tvY),
    // Jellyfin and Plex country prefixes for the US system
    ("US-PG", .pg),
    ("US-TV-14", .tv14),
    ("us:PG-13", .pg13),
    ("us/R", .r),
    ("US TV-G", .tvG),
    // "Rated" prefix, alone or after the country
    ("Rated PG-13", .pg13),
    ("RATED R", .r),
    ("Rated: G", .g),
    ("US-Rated PG", .pg),
    // Notes after the rating
    ("PG-13 (US)", .pg13),
    ("R for violence and language", .r),
    // TV content descriptors keep the base rating
    ("TV-Y7-FV", .tvY7),
    ("TV-14-LV", .tv14),
    ("TV-PG-D", .tvPg),
    ("TV-MA-LSV", .tvMa),
    ("TV-14 (DLSV)", .tv14),
]

private let adultRatings: [String] = [
    "NC-17", "nc17", "NC 17", "Rated NC-17", "US-NC-17", "X", "XXX",
    "18", "18+", "R18", "R18+", "gb/18", "DE-18", "FSK 18", "AU-R18+",
]

private let unratedValues: [String] = [
    // Missing or explicitly not rated
    "", "   ", "NR", "Not Rated", "NOT-RATED", "Unrated", "Approved", "Passed",
    // Other national systems are not mapped onto US ratings
    "gb/PG", "gb/12A", "GB-15", "de/12", "FSK-6", "au/M", "MA15+", "CA-14A", "U", "12",
    // Lookalikes and garbage
    "PG-14", "TV-PG-X", "TV-R", "GP", "M", "USPG", "US-", "RATED", "TV", "G-Rated",
]

struct ContentRatingNormalizerTests {
    @Test(arguments: canonicalRatings)
    func acceptsCanonicalUSRatings(raw: String, expected: PlinxRating) {
        #expect(ContentRatingNormalizer.classify(raw) == .rated(expected))
        #expect(PlinxRating.from(contentRating: raw) == expected)
    }

    @Test(arguments: serverSpellings)
    func acceptsServerSpellings(raw: String, expected: PlinxRating) {
        #expect(ContentRatingNormalizer.classify(raw) == .rated(expected))
        #expect(PlinxRating.from(contentRating: raw) == expected)
    }

    @Test(arguments: adultRatings)
    func classifiesAdultRatingsAsAdultOnly(raw: String) {
        #expect(ContentRatingNormalizer.classify(raw) == .adultOnly)
        #expect(PlinxRating.from(contentRating: raw) == nil)
    }

    @Test(arguments: unratedValues)
    func rejectsEverythingElseAsUnrated(raw: String) {
        #expect(ContentRatingNormalizer.classify(raw) == .unrated)
        #expect(PlinxRating.from(contentRating: raw) == nil)
    }

    @Test func treatsNilAsUnrated() {
        #expect(ContentRatingNormalizer.classify(nil) == .unrated)
    }

    @Test func adultOnlyItemsAreRejectedEvenWhenUnratedItemsAreAllowed() {
        let permissive = SafetyInterceptor(policy: .ratingOnly(max: .tvMa, allowUnrated: true))
        let adult = PlinxMediaItem(id: "1", title: "Adult", labels: [], contentRating: "NC-17")
        let unrated = PlinxMediaItem(id: "2", title: "Home video", labels: [], contentRating: nil)

        #expect(adult.isAdultOnly)
        #expect(!permissive.isAllowed(adult))
        #expect(permissive.explain(adult) == .rejected(reason: .adultOnlyRating))
        #expect(permissive.isAllowed(unrated))
    }

    @Test func contentRatingInitializerParsesThroughTheNormalizer() {
        let item = PlinxMediaItem(id: "1", title: "Show", labels: [], contentRating: "US-TV-Y7-FV")

        #expect(item.rating == .tvY7)
        #expect(!item.isAdultOnly)
        #expect(SafetyInterceptor(policy: .ratingOnly(maxMovie: .g, maxTV: .tvY7)).isAllowed(item))
        #expect(!SafetyInterceptor(policy: .ratingOnly(maxMovie: .g, maxTV: .tvY)).isAllowed(item))
    }

    @Test func unrecognizedRatingIsRejectedUnlessParentOptsIn() {
        let item = PlinxMediaItem(id: "1", title: "Import", labels: [], contentRating: "gb/12A")

        #expect(!SafetyInterceptor(policy: .ratingOnly(max: .tvMa)).isAllowed(item))
        #expect(SafetyInterceptor(policy: .ratingOnly(max: .tvMa, allowUnrated: true)).isAllowed(item))
    }
}
#endif
