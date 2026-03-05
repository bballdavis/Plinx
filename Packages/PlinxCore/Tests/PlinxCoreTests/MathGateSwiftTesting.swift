#if canImport(Testing)
import Testing
@testable import PlinxCore

private struct FixedRNG: RandomNumberGenerator {
    var values: [UInt64]
    mutating func next() -> UInt64 { values.removeFirst() }
}

struct MathGateSwiftTesting {
    @Test
    func challengeIsDeterministicWithFixedRng() {
        var rngA = FixedRNG(values: [2, 3])
        var rngB = FixedRNG(values: [2, 3])
        let sut = MathGate()
        let challengeA = sut.makeChallenge(min: 2, max: 3, rng: &rngA)
        let challengeB = sut.makeChallenge(min: 2, max: 3, rng: &rngB)
        #expect(challengeA == challengeB)
        #expect((2...3).contains(challengeA.left))
        #expect((2...3).contains(challengeA.right))
    }

    @Test
    func validate() {
        let sut = MathGate()
        let challenge = MathGate.Challenge(left: 4, right: 5)
        #expect(sut.validate(answer: 20, for: challenge))
        #expect(!sut.validate(answer: 12, for: challenge))
    }
}
#endif
