import PlinxCore
import PlinxUI
import SwiftUI

/// Picks what Play and Shuffle start in a playlist: only playable titles the
/// policy allows, so an entry the boundary let through under an older policy
/// can never start playback. `PlinxPlaybackLauncher` checks it again.
enum PlinxPlaylistPlaybackSelection {
    static func authorizedItems(
        from items: [MediaDisplayItem],
        policy: SafetyPolicy
    ) -> [MediaItem] {
        PlinxContentRules.filteredItems(items, policy: policy).compactMap(\.playableItem)
    }

    static func item(
        from items: [MediaDisplayItem],
        policy: SafetyPolicy,
        shuffled: Bool
    ) -> MediaItem? {
        let playable = authorizedItems(from: items, policy: policy)
        return shuffled ? playable.randomElement() : playable.first
    }
}

/// Kept so existing tests keep compiling; new code uses `PlinxPlaylistPlaybackSelection`.
typealias SafePlaylistPlaybackSelection = PlinxPlaylistPlaybackSelection

/// Plinx playlist page on the upstream `PlaylistDetailViewModel`.
///
/// Entries come through `SafeMediaServices`, which drops blocked titles.
/// Renaming, reordering, removing and deleting stay hidden for kids:
/// `canEdit` is false unless a parent has the gate unlocked, and every edit
/// is refused by the boundary while it is locked.
struct PlinxPlaylistDetailView: View {
    @State private var viewModel: PlaylistDetailViewModel
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let onPlay: (MediaItem) -> Void
    private let onLongPressMedia: (MediaDisplayItem) -> Void
    private let onRequestShellNavigationFocus: () -> Void
    private let contentFocusRequest: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if os(tvOS)
    @FocusState private var isBackFocused: Bool
    @State private var contentFocusGeneration = 0
    #endif

    init(
        viewModel: PlaylistDetailViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void,
        onPlay: @escaping (MediaItem) -> Void,
        onLongPressMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onRequestShellNavigationFocus: @escaping () -> Void = {},
        contentFocusRequest: Int = 0
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onPlay = onPlay
        self.onLongPressMedia = onLongPressMedia
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
        self.contentFocusRequest = contentFocusRequest
    }

    /// Entries the current policy allows, re-checked here in case the policy
    /// changed after the list was loaded.
    private var items: [MediaDisplayItem] {
        let gate = ContentSafetyGate.shared
        _ = gate.revision
        return gate.filter(viewModel.entries.map(\.media))
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            contextRow
            #endif

            Group {
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    PlinxBrandedLoadingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater")
                    )
                } else if items.isEmpty {
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
        .onChange(of: ContentSafetyGate.shared.revision) { _, _ in
            Task { await viewModel.reload() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
        #if os(tvOS)
        .onAppear {
            isBackFocused = true
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: contentFocusRequest) { _, _ in
            contentFocusGeneration &+= 1
            let generation = contentFocusGeneration
            isBackFocused = false
            Task { @MainActor in
                await Task.yield()
                guard generation == contentFocusGeneration else { return }
                isBackFocused = true
            }
        }
        #endif
    }

    @ViewBuilder
    private var playlistContent: some View {
        #if os(tvOS)
        tvPlaylistContent
        #else
        PlaylistDetailView(
            viewModel: viewModel,
            onSelectMedia: onSelectMedia,
            onPlay: { _ in play(shuffled: false) },
            onShuffle: { _ in play(shuffled: true) },
            onPlayEntry: playEntry
        )
        #endif
    }

    private func play(shuffled: Bool) {
        guard let item = PlinxPlaylistPlaybackSelection.item(
            from: items,
            policy: ContentSafetyGate.shared.policy,
            shuffled: shuffled
        ) else { return }
        onPlay(item)
    }

    private func playEntry(_ entry: PlaylistEntry) {
        guard let item = entry.media.playableItem,
              ContentSafetyGate.shared.isAllowed(item)
        else { return }
        onPlay(item)
    }

    #if os(tvOS)
    /// Entries keep their own IDs, so a title listed twice gets two cards.
    private var allowedEntries: [PlaylistEntry] {
        let gate = ContentSafetyGate.shared
        _ = gate.revision
        return viewModel.entries.filter { gate.isAllowed($0.media) }
    }

    private var tvPlaylistContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                HStack(spacing: 18) {
                    playlistActionButton(
                        title: String(localized: "common.actions.play"),
                        systemImage: "play.fill",
                        accessibilityID: "playlist.play"
                    ) {
                        play(shuffled: false)
                    }

                    playlistActionButton(
                        title: String(localized: "common.actions.shuffle"),
                        systemImage: "shuffle",
                        accessibilityID: "playlist.shuffle"
                    ) {
                        play(shuffled: true)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210, maximum: 230), spacing: 32)],
                    alignment: .leading,
                    spacing: 38
                ) {
                    ForEach(allowedEntries) { entry in
                        PlinxLibraryPortraitMediaCard(
                            media: entry.media,
                            width: 220,
                            showsLabels: true
                        ) {
                            onSelectMedia(entry.media)
                        }
                        .plinxQuickActionLongPress {
                            onLongPressMedia(entry.media)
                        }
                        .accessibilityIdentifier("playlist.item.\(entry.media.id)")
                    }
                }
            }
            .padding(.horizontal, 54)
            .padding(.vertical, 34)
        }
    }

    private func playlistActionButton(
        title: String,
        systemImage: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(minHeight: 70)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PlinxBrand.surface.opacity(0.96))
                )
        }
        .plinxTVFocusButton(style: PlinxFocusSurfaceStyle(cornerRadius: 18))
        .accessibilityIdentifier(accessibilityID)
    }

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
                    isFocused: isBackFocused,
                    style: PlinxFocusSurfaceStyle(cornerRadius: 18)
                )
            }
            .buttonStyle(PlinkButtonStyle())
            .focusEffectDisabled()
            .focused($isBackFocused)
            .onMoveCommand { direction in
                guard direction == .up else { return }
                contentFocusGeneration &+= 1
                onRequestShellNavigationFocus()
            }

            Text(viewModel.playlist.title)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 42)
        .padding(.top, PlinxTVShellMetrics.contentClearance + 16)
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.18))
    }
    #endif
}
