public struct PlinxMediaItem: Sendable, Equatable {
    public let id: String
    public let title: String
    public let labels: [String]
    public let rating: PlinxRating?

    public init(id: String, title: String, labels: [String], rating: PlinxRating?) {
        self.id = id
        self.title = title
        self.labels = labels
        self.rating = rating
    }
}
