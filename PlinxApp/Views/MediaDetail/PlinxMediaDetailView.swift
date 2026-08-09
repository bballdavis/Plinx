import SwiftUI

struct PlinxMediaDetailView: View {
    @State var viewModel: SafeMediaDetailViewModel
    var onPlay: (String, PlexItemType) -> Void
    var onShuffle: (String, PlexItemType) -> Void
    var onSelectRelated: (MediaDisplayItem) -> Void
    var onSelectParentSeries: (PlayableMediaItem) -> Void = { _ in }
    var onRequestShellNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.safetyPolicy) private var safetyPolicy
    #if os(tvOS)
    @FocusState private var isBackFocused: Bool
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isBlocked {
                blockedView
            } else {
                #if os(tvOS)
                MediaDetailTVView(
                    viewModel: viewModel.rawViewModel,
                    onPlay: onPlay,
                    onPlayFromStart: { ratingKey, type in
                        onPlay(ratingKey, type)
                    },
                    onShuffle: { ratingKey, type in
                        onShuffle(ratingKey, type)
                    },
                    onSelectMedia: onSelectRelated
                )
                #else
                MediaDetailView(
                    viewModel: viewModel.rawViewModel,
                    onPlay: onPlay,
                    onPlayFromStart: { ratingKey, type in
                        onPlay(ratingKey, type)
                    },
                    onShuffle: { ratingKey, type in
                        onShuffle(ratingKey, type)
                    },
                    onSelectMedia: onSelectRelated,
                    onSelectParentSeries: onSelectParentSeries
                )
                #endif
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            detailHeader
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("media.detail.screen")
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
        #if os(tvOS)
        .onAppear {
            isBackFocused = true
        }
        .onChange(of: contentFocusRequest) { _, _ in
            isBackFocused = true
        }
        #endif
    }

    // MARK: - Plinx back-button chrome

    private var detailHeader: some View {
        HStack(spacing: 10) {
            #if os(tvOS)
            PlinxChromeButton(systemImage: "chevron.left") {
                dismiss()
            }
            .focused($isBackFocused)
            .onMoveCommand { direction in
                guard direction == .up else { return }
                isBackFocused = false
                onRequestShellNavigationFocus()
            }

            Text(viewModel.media.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            #else
            PlinxChromeButton(systemImage: "chevron.left") {
                dismiss()
            }
            #endif
            Spacer(minLength: 0)
        }
        #if os(tvOS)
        .padding(.horizontal, 42)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        #else
        .padding(.horizontal, 16)
        .padding(.top, 4)
        #endif
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
