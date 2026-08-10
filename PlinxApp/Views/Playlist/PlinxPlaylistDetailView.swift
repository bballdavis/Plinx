import SwiftUI
import PlinxCore
import PlinxUI

struct PlinxPlaylistDetailView: View {
    @State var viewModel: SafePlaylistDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (MediaItem) -> Void
    var onRequestShellNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.safetyPolicy) private var safetyPolicy
    #if os(tvOS)
    @FocusState private var isBackFocused: Bool
    #endif

    var body: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            contextRow
            #endif

            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    PlinxBrandedLoadingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater")
                    )
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "library.browse.empty.title",
                        systemImage: "lock.shield.fill",
                        description: Text("media.playlist.noAllowedItems", tableName: "Plinx")
                    )
                } else {
                    playlistContent
                }
            }
        }
        .task {
            await viewModel.load()
        }
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

    @ViewBuilder
    private var playlistContent: some View {
        #if os(tvOS)
        PlaylistDetailTVView(
            viewModel: viewModel.rawViewModel,
            onSelectMedia: onSelectMedia,
            onPlay: { _ in play(shuffled: false) },
            onShuffle: { _ in play(shuffled: true) }
        )
        #else
        PlaylistDetailView(
            viewModel: viewModel.rawViewModel,
            onSelectMedia: onSelectMedia,
            onPlay: { _ in play(shuffled: false) },
            onShuffle: { _ in play(shuffled: true) }
        )
        #endif
    }

    private func play(shuffled: Bool) {
        guard let item = viewModel.playbackItem(shuffled: shuffled) else { return }
        onPlay(item)
    }

    #if os(tvOS)
    private var contextRow: some View {
        HStack(spacing: 24) {
            Button {
                dismiss()
            } label: {
                Label {
                    Text("common.actions.back", tableName: "Plinx")
                } icon: {
                    Image(systemName: "chevron.left")
                }
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .padding(.horizontal, 24)
                .frame(minHeight: 70)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .plinxFocusSurface(
                    isSelected: false,
                    isFocused: isBackFocused
                )
            }
            .buttonStyle(.plain)
            .focused($isBackFocused)
            .onMoveCommand { direction in
                guard direction == .up else { return }
                isBackFocused = false
                onRequestShellNavigationFocus()
            }

            Text(viewModel.playlist.title)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.18))
    }
    #endif
}
