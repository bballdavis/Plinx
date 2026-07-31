import XCTest
@testable import Plinx

final class YoutarrCapabilityExpansionTests: XCTestCase {
    func test_recommendationsPreferLocalPlexSignalMatches() throws {
        let videos = try JSONDecoder().decode(
            [YoutarrVideo].self,
            from: Data(
                """
                [
                  {
                    "youtubeId": "science0001",
                    "title": "Safe science experiment",
                    "thumbnailUrl": null,
                    "publishedAt": "2026-07-30T10:00:00Z",
                    "duration": 120,
                    "description": null,
                    "isDownloaded": false,
                    "isRequested": false,
                    "requestStatus": null,
                    "rating": 1,
                    "channelDatabaseId": 42,
                    "channelId": "UC-science",
                    "channelTitle": "Science Club",
                    "mediaType": "video"
                  },
                  {
                    "youtubeId": "sports00001",
                    "title": "Weekend sports recap",
                    "thumbnailUrl": null,
                    "publishedAt": "2026-07-30T10:00:00Z",
                    "duration": 120,
                    "description": null,
                    "isDownloaded": false,
                    "isRequested": false,
                    "requestStatus": null,
                    "rating": 1,
                    "channelDatabaseId": 43,
                    "channelId": "UC-sports",
                    "channelTitle": "Sports Desk",
                    "mediaType": "video"
                  }
                ]
                """.utf8
            )
        )

        let ranked = YoutarrRecommendationEngine.rank(
            videos,
            plexSignals: ["Science Club", "Experiments for Kids"],
            now: ISO8601DateFormatter().date(from: "2026-07-31T10:00:00Z")!
        )

        XCTAssertEqual(ranked.map(\.youtubeId), ["science0001", "sports00001"])
    }

    func test_channelRequestTargetDecodesWithoutVideoIdentifier() throws {
        let request = try JSONDecoder().decode(
            YoutarrRequest.self,
            from: Data(
                """
                {
                  "id": "00000000-0000-4000-8000-000000000017",
                  "type": "channel",
                  "status": "pending",
                  "target": {
                    "youtubeId": null,
                    "channelId": 42,
                    "channelUrl": "https://www.youtube.com/@science"
                  },
                  "createdAt": "2026-07-31T10:00:00Z",
                  "updatedAt": "2026-07-31T10:00:00Z",
                  "decidedAt": null,
                  "completedAt": null,
                  "message": null
                }
                """.utf8
            )
        )

        XCTAssertEqual(request.type, .channel)
        XCTAssertNil(request.target.youtubeId)
        XCTAssertEqual(
            YoutarrRequestPresentation.targetLabel(for: request),
            "https://www.youtube.com/@science"
        )
    }
}
