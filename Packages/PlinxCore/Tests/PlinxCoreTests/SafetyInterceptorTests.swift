#if canImport(XCTest)
import XCTest
@testable import PlinxCore

final class SafetyInterceptorTests: XCTestCase {
    func test_rejectsWhenMissingKidsLabel() {
        let item = PlinxMediaItem(id: "1", title: "Test", labels: ["Family"], rating: .g)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))
        XCTAssertFalse(sut.isAllowed(item))
    }

    func test_rejectsWhenRatingTooHigh() {
        let item = PlinxMediaItem(id: "2", title: "Test", labels: ["Kids"], rating: .pg13)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))
        XCTAssertFalse(sut.isAllowed(item))
    }

    func test_allowsWhenKidsLabelAndRatingWithinLimit() {
        let item = PlinxMediaItem(id: "3", title: "Test", labels: ["Kids"], rating: .g)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))
        XCTAssertTrue(sut.isAllowed(item))
    }

    func test_filterReturnsOnlyAllowedItems() {
        let allowed = PlinxMediaItem(id: "4", title: "Allowed", labels: ["Kids"], rating: .g)
        let blocked = PlinxMediaItem(id: "5", title: "Blocked", labels: ["Kids"], rating: .pg13)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))

        XCTAssertEqual(sut.filter([allowed, blocked]), [allowed])
    }

    func test_filterHubDropsEmptyHub() {
        let blocked = PlinxMediaItem(id: "6", title: "Blocked", labels: ["Kids"], rating: .pg13)
        let hub = PlinxHub(id: "hub-1", title: "Hub", items: [blocked])
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))

        XCTAssertNil(sut.filterHub(hub))
    }

    func test_filterHubsRemovesEmptyAndKeepsNonEmpty() {
        let allowed = PlinxMediaItem(id: "7", title: "Allowed", labels: ["Kids"], rating: .g)
        let blocked = PlinxMediaItem(id: "8", title: "Blocked", labels: ["Kids"], rating: .pg13)
        let keep = PlinxHub(id: "hub-keep", title: "Keep", items: [allowed, blocked])
        let drop = PlinxHub(id: "hub-drop", title: "Drop", items: [blocked])
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))

        XCTAssertEqual(sut.filterHubs([keep, drop]), [
            PlinxHub(id: "hub-keep", title: "Keep", items: [allowed]),
        ])
    }

    func test_labelMatchModeAnyAndAllAndNone() {
        let item = PlinxMediaItem(id: "9", title: "Item", labels: ["Kids", "Family"], rating: .g)

        let anyPolicy = SafetyPolicy(labelMatchMode: .any(["Kids", "School"]), maxMovieRating: .g, maxTVRating: .tvY)
        XCTAssertTrue(SafetyInterceptor(policy: anyPolicy).isAllowed(item))

        let allPolicy = SafetyPolicy(labelMatchMode: .all(["Kids", "Family"]), maxMovieRating: .g, maxTVRating: .tvY)
        XCTAssertTrue(SafetyInterceptor(policy: allPolicy).isAllowed(item))

        let nonePolicy = SafetyPolicy(labelMatchMode: .none, maxMovieRating: .g, maxTVRating: .tvY)
        XCTAssertTrue(SafetyInterceptor(policy: nonePolicy).isAllowed(item))
    }

    func test_explainMissingRatingAndRatingExceeds() {
        let missingRating = PlinxMediaItem(id: "10", title: "Unrated", labels: ["Kids"], rating: nil)
        let strictPolicy = SafetyPolicy(
            labelMatchMode: .required("Kids"),
            maxMovieRating: .g,
            maxTVRating: .tvY,
            allowUnrated: false
        )
        let strictInterceptor = SafetyInterceptor(policy: strictPolicy)
        XCTAssertEqual(strictInterceptor.explain(missingRating), .rejected(reason: .missingRating))

        let tooHigh = PlinxMediaItem(id: "11", title: "Too High", labels: ["Kids"], rating: .pg13)
        XCTAssertEqual(
            strictInterceptor.explain(tooHigh),
            .rejected(reason: .ratingExceedsMax(itemRating: .pg13, maxAllowed: .g))
        )
    }

    func test_explainLabelMismatch() {
        let item = PlinxMediaItem(id: "12", title: "No Label", labels: ["Family"], rating: .g)
        let policy = SafetyPolicy(labelMatchMode: .required("Kids"), maxMovieRating: .g, maxTVRating: .tvY)
        let sut = SafetyInterceptor(policy: policy)

        XCTAssertEqual(
            sut.explain(item),
            .rejected(reason: .labelMismatch(required: .required("Kids"), actual: ["Family"]))
        )
    }

    func test_explainAllowedWhenWithinPolicy() {
        let item = PlinxMediaItem(id: "13", title: "Allowed", labels: ["Kids"], rating: .g)
        let policy = SafetyPolicy(labelMatchMode: .required("Kids"), maxMovieRating: .g, maxTVRating: .tvY)
        let sut = SafetyInterceptor(policy: policy)

        XCTAssertEqual(sut.explain(item), .allowed)
    }

    func test_unratedAllowedWhenPolicyAllows() {
        let item = PlinxMediaItem(id: "14", title: "Unrated", labels: [], rating: nil)
        let sut = SafetyInterceptor(policy: .ratingOnly(max: .g, allowUnrated: true))

        XCTAssertTrue(sut.isAllowed(item))
        XCTAssertEqual(sut.explain(item), .allowed)
    }

    func test_labelAnyEmptySetIsPassThrough() {
        let item = PlinxMediaItem(id: "15", title: "Any-Empty", labels: [], rating: .g)
        let policy = SafetyPolicy(labelMatchMode: .any([]), maxMovieRating: .g, maxTVRating: .tvY)
        let sut = SafetyInterceptor(policy: policy)

        XCTAssertTrue(sut.isAllowed(item))
    }

    func test_labelAllRejectsWhenAnyMissing() {
        let item = PlinxMediaItem(id: "16", title: "All-Missing", labels: ["Kids"], rating: .g)
        let policy = SafetyPolicy(labelMatchMode: .all(["Kids", "Family"]), maxMovieRating: .g, maxTVRating: .tvY)
        let sut = SafetyInterceptor(policy: policy)

        XCTAssertFalse(sut.isAllowed(item))
    }
}
#endif
