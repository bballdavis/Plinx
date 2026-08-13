import SwiftUI
import PlinxCore
import PlinxUI

@MainActor
final class YoutarrVideoDetailViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail: YoutarrVideoDetail?

    private let youtubeID: String
    private let client: YoutarrClient

    init(video: YoutarrVideo, configuration: YoutarrConfiguration) {
        youtubeID = video.youtubeId
        client = YoutarrClient(configuration: configuration)
    }

    func load() async {
        guard phase == .idle else { return }
        phase = .loading
        do {
            detail = try await client.videoDetail(youtubeID: youtubeID)
            try Task.checkCancellation()
            phase = .ready
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(YoutarrExploreViewModel.message(for: error))
        }
    }

    func retry() async {
        phase = .idle
        await load()
    }
}
