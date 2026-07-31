import Foundation

struct YoutarrRecommendationEngine {
    static func rank(
        _ videos: [YoutarrVideo],
        plexSignals: [String],
        limit: Int = 30,
        now: Date = Date()
    ) -> [YoutarrVideo] {
        let signalTokens = tokens(plexSignals.joined(separator: " "))
        var remaining = Dictionary(uniqueKeysWithValues: videos.map { ($0.youtubeId, $0) })
        var selected: [YoutarrVideo] = []
        var recentChannels: [String] = []

        while selected.count < max(0, limit), !remaining.isEmpty {
            let best = remaining.values.max { left, right in
                let leftScore = score(
                    left,
                    signalTokens: signalTokens,
                    recentChannels: recentChannels,
                    now: now
                )
                let rightScore = score(
                    right,
                    signalTokens: signalTokens,
                    recentChannels: recentChannels,
                    now: now
                )
                if leftScore != rightScore { return leftScore < rightScore }
                let leftDate = left.publishedAt ?? ""
                let rightDate = right.publishedAt ?? ""
                if leftDate != rightDate { return leftDate < rightDate }
                return left.youtubeId > right.youtubeId
            }
            guard let best else { break }
            selected.append(best)
            remaining.removeValue(forKey: best.youtubeId)
            recentChannels.append(best.channelId)
            if recentChannels.count > 3 { recentChannels.removeFirst() }
        }
        return selected
    }

    private static func score(
        _ video: YoutarrVideo,
        signalTokens: Set<String>,
        recentChannels: [String],
        now: Date
    ) -> Double {
        let titleTokens = tokens(video.title)
        let channelTokens = tokens(video.channelTitle)
        let titleSimilarity = overlap(titleTokens, signalTokens)
        let channelAffinity = overlap(channelTokens, signalTokens)
        let freshness: Double = {
            guard let rawDate = video.publishedAt,
                  let date = ISO8601DateFormatter().date(from: rawDate) else { return 0 }
            let days = max(0, now.timeIntervalSince(date) / 86_400)
            return max(0, 1 - min(days, 365) / 365)
        }()
        let availability = video.isDownloaded ? 0.25 : 1.0
        let diversity = recentChannels.contains(video.channelId) ? 0 : 1.0
        let requestedPenalty = video.isRequested ? 0.2 : 1.0
        return (
            titleSimilarity * 0.35 +
            channelAffinity * 0.25 +
            freshness * 0.15 +
            availability * 0.15 +
            diversity * 0.10
        ) * requestedPenalty
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(
            value.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }

    private static func overlap(_ left: Set<String>, _ right: Set<String>) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }
}
