public struct PlinxMediaItem: Sendable, Equatable {
    public let id: String
    public let title: String
    public let labels: [String]
    public let rating: PlinxRating?
    /// Rated for adults only (NC-17, X, an age certificate of 18 or older): rejected by every policy, even one that allows
    /// unrated content.
    public let isAdultOnly: Bool

    public init(id: String, title: String, labels: [String], rating: PlinxRating?, isAdultOnly: Bool = false) {
        self.id = id
        self.title = title
        self.labels = labels
        self.rating = rating
        self.isAdultOnly = isAdultOnly
    }

    /// Builds the item from the server's raw rating text (`contentRating` on Plex, `OfficialRating` on Jellyfin).
    public init(id: String, title: String, labels: [String], contentRating: String?) {
        let classification = ContentRatingNormalizer.classify(contentRating)
        let rating: PlinxRating? = if case let .rated(value) = classification { value } else { nil }
        self.init(
            id: id,
            title: title,
            labels: labels,
            rating: rating,
            isAdultOnly: classification == .adultOnly
        )
    }
}
