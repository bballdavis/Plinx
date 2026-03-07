import SwiftUI

struct PlinxMediaDetailView: View {
    @State var viewModel: SafeMediaDetailViewModel
    var onPlay: (String, PlexItemType) -> Void
    var onSelectRelated: (MediaDisplayItem) -> Void

    @Environment(\.dismiss) private var dismiss

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
                    onSelectMedia: onSelectRelated
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            detailHeader
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("media.detail.screen")
    }

    // MARK: - Plinx back-button chrome

    private var detailHeader: some View {
        HStack(spacing: 10) {
            PlinxChromeButton(systemImage: "chevron.left") {
                dismiss()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
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
