import XCTest
@testable import Plinx

final class SeasonDownloadSelectionTests: XCTestCase {
    func test_seasonScopeIsFixedWhileShowScopeCanSwitchSeasons() {
        XCTAssertTrue(EpisodeDownloadSelectionScope.show.allowsSeasonSwitching)
        XCTAssertFalse(EpisodeDownloadSelectionScope.season("season-1").allowsSeasonSwitching)
    }

    func test_selectAllExcludesCompletedEpisodes() {
        let statuses: [String: DownloadStatus] = [
            "episode-1": .completed,
            "episode-2": .downloading,
        ]

        let selected = EpisodeDownloadSelectionPolicy.selectableEpisodeIDs(
            ["episode-1", "episode-2", "episode-3"],
            statusForRatingKey: { statuses[$0] }
        )

        XCTAssertEqual(selected, Set(["episode-2", "episode-3"]))
    }

    func test_submissionIsDeduplicatedOrderedAndRechecksCompletedStatus() {
        let selected = Set(["episode-3", "episode-1", "episode-2", "episode-2"])

        let submission = EpisodeDownloadSelectionPolicy.orderedSubmissionIDs(
            selected,
            statusForRatingKey: { $0 == "episode-2" ? .completed : nil }
        )

        XCTAssertEqual(submission, ["episode-1", "episode-3"])
    }
}
