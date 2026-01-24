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
}
#endif
