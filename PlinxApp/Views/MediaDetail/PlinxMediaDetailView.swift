import SwiftUI

struct PlinxMediaDetailView: View {
    @State var viewModel: SafeMediaDetailViewModel
    var onPlay: (String, PlexItemType) -> Void
    var onSelectRelated: (MediaDisplayItem) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isBlocked {
                blockedView
            } else {
                MediaDetailView(
                    viewModel: viewModel.rawViewModel,
                    onPlay: onPlay,
                    onPlayFromStart: { ratingKey, type in
                        onPlay(ratingKey, type)
                    },
                    onShuffle: { ratingKey, type in
                        onPlay(ratingKey, type)
                    },
                    onSelectMedia: onSelectRelated,
                    loadDetailsAction: {
                        await viewModel.loadDetails()
                    }
                )
            }
        }
    }

    // MARK: - Blocked

    private var blockedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.orange)
            Text("media.unavailable.title", tableName: "Plinx")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("media.unavailable.description", tableName: "Plinx")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
