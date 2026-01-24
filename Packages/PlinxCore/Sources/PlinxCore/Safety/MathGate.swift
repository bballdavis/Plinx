public struct MathGate: Sendable {
    public struct Challenge: Sendable, Equatable {
        public let left: Int
        public let right: Int

        public var prompt: String {
            "\(left) × \(right)"
        }

        public var answer: Int {
            left * right
        }
    }

    public init() {}

    public func makeChallenge(
        min: Int = 2,
        max: Int = 9,
        rng: inout some RandomNumberGenerator
    ) -> Challenge {
        let left = Int.random(in: min...max, using: &rng)
        let right = Int.random(in: min...max, using: &rng)
        return Challenge(left: left, right: right)
    }

    public func validate(answer: Int, for challenge: Challenge) -> Bool {
        answer == challenge.answer
    }
}
