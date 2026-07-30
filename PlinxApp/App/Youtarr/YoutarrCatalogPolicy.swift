import Foundation
import PlinxCore

enum YoutarrCatalogCapabilityPolicy {
    static func canBrowse(_ capabilities: YoutarrCapabilities) -> Bool {
        capabilities.features.catalog && capabilities.scopes.contains(.catalogRead)
    }
}

enum YoutarrCatalogPresentation {
    /// Preserves the server's recency order except when the same channel would
    /// occupy more than `maximumConsecutive` cards and another channel is
    /// already available later in the loaded page.
    static func diversified(
        _ videos: [YoutarrVideo],
        maximumConsecutive: Int = 2
    ) -> [YoutarrVideo] {
        guard maximumConsecutive > 0, videos.count > maximumConsecutive else {
            return videos
        }

        var remaining = videos
        var result: [YoutarrVideo] = []
        var lastChannel: String?
        var consecutive = 0

        while !remaining.isEmpty {
            var selectedIndex = 0
            if consecutive >= maximumConsecutive,
               let lastChannel,
               let alternate = remaining.firstIndex(where: {
                   $0.channelId != lastChannel
               }) {
                selectedIndex = alternate
            }

            let selected = remaining.remove(at: selectedIndex)
            if selected.channelId == lastChannel {
                consecutive += 1
            } else {
                lastChannel = selected.channelId
                consecutive = 1
            }
            result.append(selected)
        }

        return result
    }
}

/// Defense-in-depth filtering applied after Youtarr has enforced its key
/// policy. Unknown rating values and unapproved media types fail closed.
struct YoutarrExploreSafetyPolicy {
    private let serverPolicy: YoutarrCapabilities.Policy
    private let localPolicy: SafetyPolicy

    init(serverPolicy: YoutarrCapabilities.Policy, localPolicy: SafetyPolicy) {
        self.serverPolicy = serverPolicy
        self.localPolicy = localPolicy
    }

    func allows(_ video: YoutarrVideo) -> Bool {
        let mediaType = video.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedMediaTypes = Set(serverPolicy.allowedMediaTypes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        let canonicalMediaTypes: Set<String> = ["video", "short", "livestream"]
        guard canonicalMediaTypes.contains(mediaType),
              allowedMediaTypes.contains(mediaType) else {
            return false
        }
        guard let serverMaximum = serverPolicy.maxRatingLevel,
              (1...4).contains(serverMaximum) else {
            return false
        }

        guard let rating = video.rating else {
            return serverPolicy.allowUnrated && localPolicy.allowUnrated
        }

        switch rating {
        case .level(let level):
            guard (1...4).contains(level) else { return false }
            return level <= serverMaximum && level <= localMaximumLevel

        case .label(let label):
            guard let parsed = PlinxRating.from(contentRating: label) else {
                return false
            }
            let localMaximum = parsed.isTVRating
                ? localPolicy.maxTVRating
                : localPolicy.maxMovieRating
            guard parsed <= localMaximum else { return false }
            return Self.level(for: parsed) <= serverMaximum
        }
    }

    private var localMaximumLevel: Int {
        min(
            Self.level(for: localPolicy.maxMovieRating),
            Self.level(for: localPolicy.maxTVRating)
        )
    }

    private static func level(for rating: PlinxRating) -> Int {
        switch rating {
        case .tvY, .g:
            return 1
        case .tvY7, .tvG, .pg, .tvPg:
            return 2
        case .pg13, .tv14:
            return 3
        case .r, .tvMa:
            return 4
        }
    }
}
