#if canImport(XCTest)
import XCTest
@testable import PlinxCore

private struct FixedRNG: RandomNumberGenerator {
    var values: [UInt64]
    mutating func next() -> UInt64 { values.removeFirst() }
}

final class MathGateTests: XCTestCase {
    func test_challengeIsDeterministicWithFixedRng() {
        var rng = FixedRNG(values: [2, 3])
        let sut = MathGate()
        let challenge = sut.makeChallenge(min: 2, max: 3, rng: &rng)
        XCTAssertEqual(challenge, .init(left: 2, right: 3))
    }

    func test_validate() {
        let sut = MathGate()
        let challenge = MathGate.Challenge(left: 4, right: 5)
        XCTAssertTrue(sut.validate(answer: 20, for: challenge))
        XCTAssertFalse(sut.validate(answer: 12, for: challenge))
    }
}
#endif
