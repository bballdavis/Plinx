#if canImport(Testing)
import Testing
import SwiftUI
@testable import PlinxCore

struct SafetyPolicyTests {
    @Test func defaultRatingOnlyUsesConservativeMovieAndTVCeilings() {
        let policy = SafetyPolicy.ratingOnly()

        #expect(policy.maxMovieRating == .g)
        #expect(policy.maxTVRating == .tvY)
        #expect(!policy.allowUnrated)
    }

    @Test func explicitSingleCeilingRemainsAvailableForCallersThatNeedIt() {
        let policy = SafetyPolicy.ratingOnly(max: .pg, allowUnrated: false)

        #expect(policy.maxMovieRating == .pg)
        #expect(policy.maxTVRating == .pg)
        #expect(!policy.allowUnrated)
    }

    @MainActor
    @Test func unInjectedEnvironmentPolicyFailsClosed() {
        let policy = EnvironmentValues().safetyPolicy

        #expect(policy.maxMovieRating == .g)
        #expect(policy.maxTVRating == .tvY)
        #expect(!policy.allowUnrated)
    }

    @Test func defaultInterceptorRejectsUnratedContent() {
        let unrated = PlinxMediaItem(id: "unrated", title: "Unrated", labels: [], rating: nil)

        #expect(!SafetyInterceptor().isAllowed(unrated))
    }
}
#endif
