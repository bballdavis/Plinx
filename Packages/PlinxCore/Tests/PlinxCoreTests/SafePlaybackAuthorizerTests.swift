import XCTest
@testable import PlinxCore

final class SafePlaybackAuthorizerTests: XCTestCase {
    func test_allowsItemAtMovieBoundary() {
        let authorizer = PolicyPlaybackAuthorizer(
            policy: .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        )

        XCTAssertEqual(authorizer.decision(for: item(rating: .pg)), .allowed)
    }

    func test_rejectsMovieAboveBoundary() {
        let authorizer = PolicyPlaybackAuthorizer(
            policy: .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        )

        XCTAssertEqual(
            authorizer.decision(for: item(rating: .r)),
            .rejected(reason: .ratingExceedsMax(itemRating: .r, maxAllowed: .pg))
        )
    }

    func test_rejectsMissingRatingUnlessParentOptsIn() {
        let strict = PolicyPlaybackAuthorizer(
            policy: .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false)
        )
        let permissive = PolicyPlaybackAuthorizer(
            policy: .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: true)
        )

        XCTAssertEqual(strict.decision(for: item(rating: nil)), .rejected(reason: .missingRating))
        XCTAssertEqual(permissive.decision(for: item(rating: nil)), .allowed)
    }

    private func item(rating: PlinxRating?) -> PlinxMediaItem {
        PlinxMediaItem(id: "fixture", title: "Fixture", labels: [], rating: rating)
    }
}
