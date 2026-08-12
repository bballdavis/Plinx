#if os(tvOS)
import SwiftUI
import PlinxUI

@MainActor
struct AppleTVProfileSwitcherUITestHarness: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var presentsAsModal: Bool
    private let modal: Bool

    init(
        context: PlexAPIContext,
        sessionManager: SessionManager,
        modal: Bool
    ) {
        let viewModel = ProfileSwitcherViewModel(
            context: context,
            sessionManager: sessionManager
        )
        viewModel.users = [
            PlexHomeUser(
                id: 1,
                uuid: "fixture-kids",
                title: "Kids",
                username: "kids",
                email: nil,
                friendlyName: "Kids",
                thumb: nil,
                protected: true,
                pin: nil
            ),
            PlexHomeUser(
                id: 2,
                uuid: "fixture-family",
                title: "Family",
                username: nil,
                email: nil,
                friendlyName: "Family",
                thumb: nil,
                protected: false,
                pin: nil
            )
        ]
        _viewModel = State(initialValue: viewModel)
        _presentsAsModal = State(initialValue: !modal)
        self.modal = modal
    }

    var body: some View {
        if modal {
            ZStack {
                PlinxAmbientBackground(intensity: .restrained)
                Text("Profile modal fixture")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .sheet(isPresented: $presentsAsModal) {
                profileSwitcher
                    .presentationBackground(PlinxBrand.shell)
            }
            .task { presentsAsModal = true }
        } else {
            profileSwitcher
        }
    }

    private var profileSwitcher: some View {
        PlinxProfileSwitcherTVView(
            viewModel: viewModel,
            loadsUsersOnAppear: false
        )
    }
}

struct AppleTVPlayerControlsUITestHarness: View {
    @State private var position = 112.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerControlsTVView(
                media: nil,
                isPaused: true,
                videoResolution: "4K",
                videoFormatBadge: nil,
                position: $position,
                duration: 1_800,
                bufferedAhead: 30,
                bufferBasePosition: position,
                isScrubbing: false,
                onShowAudioSettings: {},
                onShowSubtitleSettings: {},
                onSeekBackward: {},
                onPlayPause: {},
                onSeekForward: {},
                seekBackwardSeconds: 10,
                seekForwardSeconds: 30,
                onScrubbingChanged: { _ in },
                skipMarkerTitle: "Skip Intro",
                onSkipMarker: {},
                onUserInteraction: {},
                isSharePlay: false
            )
        }
    }
}

struct AppleTVPlayerTracksUITestHarness: View {
    var body: some View {
        PlayerTrackSelectionView(
            titleKey: "player.settings.subtitles.title",
            tracks: [],
            selectedTrackID: nil,
            showOffOption: true,
            onSelect: { _ in },
            onClose: {}
        )
    }
}

struct AppleTVQuickActionUITestHarness: View {
    @State private var isShowingActions = false
    @State private var shortActivationCount = 0
    @FocusState private var isCardFocused: Bool
    @FocusState private var focusedAction: String?

    var body: some View {
        ZStack {
            PlinxAmbientBackground(intensity: .restrained)

            Button {
                shortActivationCount += 1
            } label: {
                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PlinxBrand.surface)
                        .frame(width: 260, height: 360)
                        .overlay {
                            Image(systemName: "film.fill")
                                .font(.system(size: 70))
                                .foregroundStyle(.white.opacity(0.86))
                        }
                    Text("Fixture Movie")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .focused($isCardFocused)
            .plinxTVFocusButton(style: PlinxFocusSurfaceStyle(cornerRadius: 18))
            .plinxQuickActionLongPress { isShowingActions = true }
            .accessibilityIdentifier("quickAction.fixture.card")

            if isShowingActions {
                Color.black.opacity(0.5).ignoresSafeArea()

                VStack(spacing: 18) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityIdentifier("quickAction.sheet")

                    Text("Fixture Movie")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    quickActionButton("Play", id: "play", systemImage: "play.fill")
                    quickActionButton("Mark as Watched", id: "toggle-watched", systemImage: "checkmark.circle")
                    quickActionButton("More Info", id: "go-details", systemImage: "info.circle")
                    quickActionButton("Cancel", id: "cancel", systemImage: "xmark")
                }
                .padding(28)
                .frame(width: 620)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(PlinxBrand.shell.opacity(0.98))
                )
                .onAppear {
                    Task { @MainActor in
                        await Task.yield()
                        focusedAction = "play"
                    }
                }
                .onExitCommand { dismissActions() }
            }

            Text("\(shortActivationCount)")
                .accessibilityIdentifier("quickAction.fixture.shortActivationCount")
                .accessibilityValue("\(shortActivationCount)")
                .opacity(0.001)
        }
        .task { isCardFocused = true }
    }

    private func quickActionButton(
        _ title: String,
        id: String,
        systemImage: String
    ) -> some View {
        Button {
            dismissActions()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(PlinxBrand.surface)
                )
        }
        .focused($focusedAction, equals: id)
        .plinxTVFocusButton(style: PlinxFocusSurfaceStyle(cornerRadius: 20))
        .accessibilityIdentifier(
            id == "cancel" ? "quickAction.cancel" : "quickAction.option.\(id)"
        )
        .accessibilityValue("darkPlinxQuickActionWithGradientFocus")
    }

    private func dismissActions() {
        isShowingActions = false
        focusedAction = nil
        Task { @MainActor in
            await Task.yield()
            isCardFocused = true
        }
    }
}

struct AppleTVLibraryLoadingUITestHarness: View {
    var body: some View {
        VStack(spacing: 28) {
            loadingRow("library.recommended.loading", id: "library.loading.recommended")
            loadingRow("library.browse.loading", id: "library.loading.browse")
            loadingRow("library.browse.filters.loading", id: "library.loading.filters")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlinxBrand.shell)
    }

    private func loadingRow(_ key: LocalizedStringKey, id: String) -> some View {
        HStack(spacing: 18) {
            ProgressView()
                .tint(Color.accentColor)
                .accessibilityHidden(true)
            Text(key, tableName: "Plinx")
                .font(.title3)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
#endif
