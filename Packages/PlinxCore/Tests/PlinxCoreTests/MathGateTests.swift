#if canImport(XCTest)
import XCTest
@testable import PlinxCore

private struct FixedRNG: RandomNumberGenerator {
    var values: [UInt64]
    mutating func next() -> UInt64 { values.removeFirst() }
}

final class MathGateTests: XCTestCase {
    func test_challengeIsDeterministicWithFixedRng() {
        var rngA = FixedRNG(values: [2, 3])
        var rngB = FixedRNG(values: [2, 3])
        let sut = MathGate()
        let challengeA = sut.makeChallenge(min: 2, max: 3, rng: &rngA)
        let challengeB = sut.makeChallenge(min: 2, max: 3, rng: &rngB)
        XCTAssertEqual(challengeA, challengeB)
        XCTAssertTrue((2...3).contains(challengeA.left))
        XCTAssertTrue((2...3).contains(challengeA.right))
    }

    func test_validate() {
        let sut = MathGate()
        let challenge = MathGate.Challenge(left: 4, right: 5)
        XCTAssertTrue(sut.validate(answer: 20, for: challenge))
        XCTAssertFalse(sut.validate(answer: 12, for: challenge))
    }

    func test_challengePromptAndAnswer() {
        let challenge = MathGate.Challenge(left: 3, right: 4)
        XCTAssertEqual(challenge.prompt, "3 × 4")
        XCTAssertEqual(challenge.answer, 12)
    }
}
#endif
