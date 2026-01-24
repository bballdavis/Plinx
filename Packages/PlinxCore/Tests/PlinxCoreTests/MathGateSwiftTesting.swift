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
        var rng = FixedRNG(values: [2, 3])
        let sut = MathGate()
        let challenge = sut.makeChallenge(min: 2, max: 3, rng: &rng)
        #expect(challenge == .init(left: 2, right: 3))
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
