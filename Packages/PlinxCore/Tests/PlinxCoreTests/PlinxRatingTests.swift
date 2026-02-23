// ─────────────────────────────────────────────────────────────────────────────
// PlinxRatingTests.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// Tests for PlinxRating: parsing, ordering, isTVRating, isMovieRating.
// All cases run without a simulator.
//
// References: development/UI_TESTING_STRATEGY.md — "Logic" layer
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(Testing)
import Testing
@testable import PlinxCore

// MARK: - Parsing

struct PlinxRatingParsingTests {

    // Standard strings as they appear in Plex metadata
    @Test func parsesStandardPlexRatings() {
        #expect(PlinxRating.from(contentRating: "G")     == .g)
        #expect(PlinxRating.from(contentRating: "PG")    == .pg)
        #expect(PlinxRating.from(contentRating: "PG-13") == .pg13)
        #expect(PlinxRating.from(contentRating: "R")     == .r)
        #expect(PlinxRating.from(contentRating: "TV-Y")  == .tvY)
        #expect(PlinxRating.from(contentRating: "TV-Y7") == .tvY7)
        #expect(PlinxRating.from(contentRating: "TV-PG") == .tvPg)
        #expect(PlinxRating.from(contentRating: "TV-14") == .tv14)
        #expect(PlinxRating.from(contentRating: "TV-MA") == .tvMa)
    }

    @Test func toleratesLowercaseInput() {
        #expect(PlinxRating.from(contentRating: "pg")    == .pg)
        #expect(PlinxRating.from(contentRating: "tv-pg") == .tvPg)
        #expect(PlinxRating.from(contentRating: "tv-ma") == .tvMa)
    }

    @Test func toleratesWhitespace() {
        #expect(PlinxRating.from(contentRating: "  PG-13  ") == .pg13)
        #expect(PlinxRating.from(contentRating: " TV-Y7 ")   == .tvY7)
    }

    @Test func toleratesUnderscoreDelimiter() {
        // Some metadata sources use TV_PG instead of TV-PG
        #expect(PlinxRating.from(contentRating: "TV_PG") == .tvPg)
        #expect(PlinxRating.from(contentRating: "PG_13") == .pg13)
    }

    @Test func returnsNilForUnknownRating() {
        #expect(PlinxRating.from(contentRating: "NR")     == nil)
        #expect(PlinxRating.from(contentRating: "NOT-RATED") == nil)
        #expect(PlinxRating.from(contentRating: "")       == nil)
    }

    @Test func returnsNilForNilInput() {
        #expect(PlinxRating.from(contentRating: nil) == nil)
    }
}

// MARK: - Classification

struct PlinxRatingClassificationTests {

    @Test func tvRatingsAreClassifiedCorrectly() {
        let tvRatings: [PlinxRating] = [.tvY, .tvY7, .tvPg, .tv14, .tvMa]
        for rating in tvRatings {
            #expect(rating.isTVRating, "Expected \(rating) to be a TV rating")
            #expect(!rating.isMovieRating, "Expected \(rating) not to be a movie rating")
        }
    }

    @Test func movieRatingsAreClassifiedCorrectly() {
        let movieRatings: [PlinxRating] = [.g, .pg, .pg13, .r]
        for rating in movieRatings {
            #expect(rating.isMovieRating, "Expected \(rating) to be a movie rating")
            #expect(!rating.isTVRating, "Expected \(rating) not to be a TV rating")
        }
    }

    @Test func tvRatingsPropertyContainsAllTVRatings() {
        let tv = Set(PlinxRating.tvRatings)
        #expect(tv.contains(.tvY))
        #expect(tv.contains(.tvY7))
        #expect(tv.contains(.tvPg))
        #expect(tv.contains(.tv14))
        #expect(tv.contains(.tvMa))
        #expect(!tv.contains(.g))
        #expect(!tv.contains(.pg13))
    }

    @Test func movieRatingsPropertyContainsAllMovieRatings() {
        let movie = Set(PlinxRating.movieRatings)
        #expect(movie.contains(.g))
        #expect(movie.contains(.pg))
        #expect(movie.contains(.pg13))
        #expect(movie.contains(.r))
        #expect(!movie.contains(.tvY))
        #expect(!movie.contains(.tvMa))
    }
}

// MARK: - Ordering

struct PlinxRatingOrderingTests {

    @Test func movieRatingsAreOrderedByRestrictiveness() {
        #expect(PlinxRating.g   < .pg)
        #expect(PlinxRating.pg  < .pg13)
        #expect(PlinxRating.pg13 < .r)
    }

    @Test func tvRatingsAreOrderedByRestrictiveness() {
        #expect(PlinxRating.tvY  < .tvY7)
        #expect(PlinxRating.tvY7 < .tvPg)
        #expect(PlinxRating.tvPg < .tv14)
        #expect(PlinxRating.tv14 < .tvMa)
    }

    @Test func gIsLessThanPG13() {
        #expect(PlinxRating.g < .pg13)
    }

    @Test func tvYIsLessThanTVMA() {
        #expect(PlinxRating.tvY < .tvMa)
    }

    @Test func ratingsAreNotLessThanThemselves() {
        for rating in PlinxRating.allCases {
            #expect(!(rating < rating))
        }
    }
}
#endif
