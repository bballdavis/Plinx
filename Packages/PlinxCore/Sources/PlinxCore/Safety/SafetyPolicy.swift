public struct SafetyPolicy: Sendable, Equatable {
    public let requiredLabel: String
    public let maxRating: PlinxRating

    public init(requiredLabel: String = "Kids", maxRating: PlinxRating = .g) {
        self.requiredLabel = requiredLabel
        self.maxRating = maxRating
    }
}
