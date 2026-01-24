#if canImport(Testing)
import Testing
@testable import PlinxCore

struct SafetyInterceptorSwiftTesting {
    @Test
    func rejectsWhenMissingKidsLabel() {
        let item = PlinxMediaItem(id: "1", title: "Test", labels: ["Family"], rating: .g)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))
        #expect(!sut.isAllowed(item))
    }

    @Test
    func rejectsWhenRatingTooHigh() {
        let item = PlinxMediaItem(id: "2", title: "Test", labels: ["Kids"], rating: .pg13)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))
        #expect(!sut.isAllowed(item))
    }

    @Test
    func allowsWhenKidsLabelAndRatingWithinLimit() {
        let item = PlinxMediaItem(id: "3", title: "Test", labels: ["Kids"], rating: .g)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))
        #expect(sut.isAllowed(item))
    }

    @Test
    func filterReturnsOnlyAllowedItems() {
        let allowed = PlinxMediaItem(id: "4", title: "Allowed", labels: ["Kids"], rating: .g)
        let blocked = PlinxMediaItem(id: "5", title: "Blocked", labels: ["Kids"], rating: .pg13)
        let sut = SafetyInterceptor(policy: SafetyPolicy(requiredLabel: "Kids", maxRating: .g))

        #expect(sut.filter([allowed, blocked]) == [allowed])
    }
}
#endif
