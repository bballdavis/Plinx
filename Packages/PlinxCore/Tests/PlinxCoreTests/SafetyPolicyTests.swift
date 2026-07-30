#if canImport(Testing)
import Testing
@testable import PlinxCore

struct SafetyPolicyTests {
    @Test func defaultRatingOnlyUsesConservativeMovieAndTVCeilings() {
        let policy = SafetyPolicy.ratingOnly()

        #expect(policy.maxMovieRating == .g)
        #expect(policy.maxTVRating == .tvY)
        #expect(policy.allowUnrated)
    }

    @Test func explicitSingleCeilingRemainsAvailableForCallersThatNeedIt() {
        let policy = SafetyPolicy.ratingOnly(max: .pg, allowUnrated: false)

        #expect(policy.maxMovieRating == .pg)
        #expect(policy.maxTVRating == .pg)
        #expect(!policy.allowUnrated)
    }
}
#endif
