import SwiftUI

#if !os(tvOS)
struct SeasonDownloadUITestHarness: View {
    @Environment(PlexAPIContext.self) private var context
    @Environment(\.safetyPolicy) private var safetyPolicy

    var body: some View {
        NavigationStack {
            NavigationLink {
                SeasonDownloadFixtureView(
                    context: context,
                    safetyPolicy: safetyPolicy
                )
            } label: {
                Text("More Info")
            }
            .accessibilityIdentifier("season.fixture.moreInfo")
        }
    }
}
private struct SeasonDownloadFixtureView: View {
    @State private var viewModel: MediaDetailViewModel
    let safetyPolicy: SafetyPolicy

    init(context: PlexAPIContext, safetyPolicy: SafetyPolicy) {
        let season = Self.mediaItem(
            id: "season-1",
            title: "Season 1",
            type: .season,
            parentRatingKey: "show-1",
            index: 1
        )
        let model = MediaDetailViewModel(
            media: PlayableMediaItem(mediaItem: season)!,
            context: context,
            resolutionMode: .selectedMedia
        )
        model.selectedSeasonId = season.id
        model.episodes = (1...3).map { index in
            Self.mediaItem(
                id: "episode-\(index)",
                title: "Fixture Episode \(index)",
                type: .episode,
                parentRatingKey: season.id,
                grandparentRatingKey: "show-1",
                index: index
            )
        }
        _viewModel = State(initialValue: model)
        self.safetyPolicy = safetyPolicy
    }

    var body: some View {
        PlinxMediaDetailView(
            viewModel: SafeMediaDetailViewModel(
                inner: viewModel,
                policy: safetyPolicy
            ),
            onPlay: { _, _ in },
            onShuffle: { _, _ in },
            onSelectRelated: { _ in }
        )
    }

    private static func mediaItem(
        id: String,
        title: String,
        type: PlexItemType,
        parentRatingKey: String?,
        grandparentRatingKey: String? = nil,
        index: Int
    ) -> MediaItem {
        MediaItem(
            id: id,
            guid: "fixture://\(id)",
            summary: nil,
            title: title,
            type: type,
            parentRatingKey: parentRatingKey,
            grandparentRatingKey: grandparentRatingKey,
            genres: [],
            year: nil,
            duration: 1_200,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: "TV-Y",
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: "Fixture Show",
            parentTitle: "Season 1",
            parentIndex: 1,
            index: index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        )
    }
}
#endif
