import Observation
import PlinxCore
import PlinxUI
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
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isBlocked || !ReleaseScreenshotCaptureMode.allowsDetail(
                ratingKey: viewModel.media.id
            ) {
                blockedView
            } else {
                #if os(tvOS)
                PlinxMediaDetailTVView(
                    viewModel: viewModel.rawViewModel,
                    onPlay: onPlay,
                    onPlayFromStart: { ratingKey, type in
                        onPlay(ratingKey, type)
                    },
                    onSelectMedia: onSelectRelated,
                    onDismiss: { dismiss() },
                    onRequestShellNavigationFocus: onRequestShellNavigationFocus,
                    contentFocusRequest: contentFocusRequest
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
        #if !os(tvOS)
            .safeAreaInset(edge: .top, spacing: 0) {
                detailHeader
            }
        #endif
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("media.detail.screen")
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
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

#if os(tvOS)
/// Plinx-owned tvOS presentation for media detail.
///
/// Strimr continues to own the detail model and reusable content sections. This
/// shell supplies the television-specific reading order, focus behavior, and
/// backdrop treatment without turning a Home hero into a detail page.
private struct PlinxMediaDetailTVView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(\.sharePlayPresentationPolicy) private var sharePlayPresentationPolicy
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: MediaDetailViewModel
    @State private var focusedMedia: MediaItem?
    @State private var hasHandledInitialEpisodePosition = false
    @State private var hasUserSelectedSeason = false
    @State private var isSummaryExpanded = false
    @FocusState private var isBackFocused: Bool

    private let onPlay: (String, PlexItemType) -> Void
    private let onPlayFromStart: (String, PlexItemType) -> Void
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let onDismiss: () -> Void
    private let onRequestShellNavigationFocus: () -> Void
    private let contentFocusRequest: Int

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, PlexItemType) -> Void,
        onPlayFromStart: @escaping (String, PlexItemType) -> Void,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void,
        onDismiss: @escaping () -> Void,
        onRequestShellNavigationFocus: @escaping () -> Void,
        contentFocusRequest: Int
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onSelectMedia = onSelectMedia
        self.onDismiss = onDismiss
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
        self.contentFocusRequest = contentFocusRequest
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        GeometryReader { proxy in
            let horizontalInset = TvBrowseHeroMetrics.homeAlignedContentInset
            let safeContentWidth = max(0, proxy.size.width - horizontalInset * 2)
            // Keep More Info substantially wider than its former reading
            // column while always honoring the shell's horizontal safe guide.
            let detailWidth = min(proxy.size.width * 0.78, safeContentWidth)

            ZStack(alignment: .topLeading) {
                MediaBackdropGradient(colors: bindableViewModel.backdropGradient)
                    .ignoresSafeArea()

                TvPinnedHeroBackdrop(
                    media: focusedMedia ?? bindableViewModel.media.mediaItem,
                    identityGuideHeight: proxy.size.height,
                    bottomFadeStartLocation: TvBrowseHeroMetrics.default.backdropFadeStartLocation,
                    showsIdentity: false,
                    fillsBase: false
                )
                .ignoresSafeArea()

                // The artwork is deliberately supportive. This source-aware
                // gradient preserves readable detail text even when a backdrop
                // is light or has busy artwork on its leading side.
                LinearGradient(
                    colors: [
                        Color.appBackground.opacity(0.98),
                        Color.appBackground.opacity(0.90),
                        Color.appBackground.opacity(0.58),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 38) {
                        header

                        VStack(alignment: .leading, spacing: 38) {
                            detailOverview
                            detailRows
                        }
                            .frame(width: detailWidth, alignment: .leading)
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, 56)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: PlinxTVShellMetrics.contentClearance + 12)
                    .accessibilityHidden(true)
            }
        }
        .task {
            await bindableViewModel.loadDetails()
        }
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            Task { await bindableViewModel.loadDetails() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onAppear {
            if focusedMedia == nil {
                focusedMedia = bindableViewModel.media.mediaItem
            }
            isBackFocused = true
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onChange(of: bindableViewModel.media) { oldValue, newValue in
            if focusedMedia == nil || focusedMedia?.id == oldValue.id {
                focusedMedia = newValue.mediaItem
            }
        }
        .onChange(of: contentFocusRequest) { _, _ in
            // Returning from shell chrome always restores a clear, predictable
            // first focus target instead of leaving focus in an offscreen row.
            isBackFocused = false
            Task { @MainActor in
                await Task.yield()
                isBackFocused = true
            }
        }
        .onExitCommand(perform: onDismiss)
        .toolbar(.hidden, for: .tabBar)
        .alert(
            "sharePlay.error.title",
            isPresented: Binding(
                get: { sharePlayCoordinator.errorMessage != nil },
                set: { if !$0 { sharePlayCoordinator.errorMessage = nil } }
            )
        ) {
            Button("common.actions.done") {
                sharePlayCoordinator.errorMessage = nil
            }
        } message: {
            Text(sharePlayCoordinator.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(TvPillButtonStyle(isSelected: false, cornerRadius: 16))
            .focusEffectDisabled()
            .focused($isBackFocused)
            .accessibilityLabel(Text("common.actions.back", tableName: "Plinx"))
            .onMoveCommand { direction in
                guard direction == .up else { return }
                onRequestShellNavigationFocus()
            }

            Spacer(minLength: 0)
        }
    }

    private var detailOverview: some View {
        VStack(alignment: .leading, spacing: 22) {
            titleSection
            actionStack
            badgesSection
            ratingsSection

            if let tagline = viewModel.media.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            summarySection

            genresSection

            if let studio = viewModel.media.studio, !studio.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("media.detail.studio")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(studio)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.88))
                }
            }

            detailStatus
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let titleLogoURL = viewModel.titleLogoURL {
                AsyncImage(url: titleLogoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 620, maxHeight: 170, alignment: .leading)
                            .accessibilityLabel(Text(verbatim: viewModel.detailPrimaryLabel))
                    } else {
                        titleText
                    }
                }
            } else {
                titleText
            }

            if let secondary = viewModel.detailSecondaryLabel, !secondary.isEmpty {
                Text(secondary)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
            }

            if let tertiary = viewModel.detailTertiaryLabel, !tertiary.isEmpty {
                Text(tertiary)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private var titleText: some View {
        Text(viewModel.detailPrimaryLabel)
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(3)
            .minimumScaleFactor(0.72)
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = viewModel.media.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.84))
                    .multilineTextAlignment(.leading)
                    .lineLimit(isSummaryExpanded ? nil : 4)

                Button {
                    isSummaryExpanded.toggle()
                } label: {
                    Label {
                        Text(
                            isSummaryExpanded ? "common.actions.showLess" : "common.actions.readMore",
                            tableName: "Plinx"
                        )
                    } icon: {
                        Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.headline.weight(.semibold))
                }
                .buttonStyle(TvPillButtonStyle(isSelected: false, cornerRadius: 14))
                .focusEffectDisabled()
                .accessibilityIdentifier("media.detail.summary-disclosure")
            }
        }
    }

    @ViewBuilder
    private var badgesSection: some View {
        if viewModel.yearText != nil || viewModel.runtimeText != nil || viewModel.media.contentRating != nil {
            HStack(spacing: 10) {
                if let year = viewModel.yearText {
                    detailBadge(year)
                }

                if let runtime = viewModel.runtimeText {
                    detailBadge(runtime, systemImage: "clock")
                }

                if let contentRating = viewModel.media.contentRating {
                    detailBadge(contentRating)
                }
            }
        }
    }

    @ViewBuilder
    private var ratingsSection: some View {
        if !viewModel.media.ratings.isEmpty {
            HStack(spacing: 16) {
                ForEach(viewModel.media.ratings.indices, id: \.self) { index in
                    MediaRatingLabel(rating: viewModel.media.ratings[index], iconHeight: 22)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    @ViewBuilder
    private var genresSection: some View {
        if !viewModel.media.genres.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("media.detail.genres")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.media.genres, id: \.self) { genre in
                            detailBadge(genre)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var detailStatus: some View {
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
        }

        if let watchActionErrorMessage = viewModel.watchActionErrorMessage {
            Label(watchActionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
        }

        if viewModel.isLoading {
            ProgressView("media.detail.updating")
                .font(.headline)
                .tint(.white)
        }
    }

    private func detailBadge(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 32) {
            if viewModel.media.type == .show {
                seasonsSection
            }

            CastSection(viewModel: viewModel)
            RelatedHubsSection(viewModel: viewModel, onSelectMedia: onSelectMedia)
        }
    }

    private var actionStack: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                playButton

                if viewModel.shouldShowPlayFromStartButton {
                    playFromStartButton
                }

                watchToggleButton
            }

            if sharePlayPresentationPolicy == .enabled {
                sharePlayButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)

                PlinxTVDetailPlayProgressIcon(progress: viewModel.primaryActionProgress)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.primaryActionTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if let detail = viewModel.primaryActionDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .plinxTVDetailActionSurface(isPrimary: true)
        .disabled(viewModel.primaryActionRatingKey == nil)
        .accessibilityIdentifier("media.detail.play")
    }

    private var playFromStartButton: some View {
        Button(action: handlePlayFromStart) {
            Image(systemName: "arrow.counterclockwise")
                .font(.title2.weight(.semibold))
                .frame(width: PlinxTVDetailActionMetrics.height, height: PlinxTVDetailActionMetrics.height)
        }
        .plinxTVDetailActionSurface()
        .accessibilityLabel(Text("media.detail.playFromStart", tableName: "Plinx"))
        .accessibilityIdentifier("media.detail.play-from-start")
    }

    private var watchToggleButton: some View {
        Button {
            Task { await viewModel.toggleWatchStatus() }
        } label: {
            if viewModel.isUpdatingWatchStatus {
                ProgressView()
                    .tint(.white)
                    .frame(width: PlinxTVDetailActionMetrics.height, height: PlinxTVDetailActionMetrics.height)
            } else {
                Image(systemName: viewModel.isWatched ? "arrow.uturn.backward" : "checkmark")
                    .font(.title2.weight(.semibold))
                    .frame(width: PlinxTVDetailActionMetrics.height, height: PlinxTVDetailActionMetrics.height)
            }
        }
        .plinxTVDetailActionSurface()
        .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)
        .accessibilityLabel(watchActionTitle)
        .accessibilityIdentifier("media.detail.watch")
    }

    private var sharePlayButton: some View {
        Button {
            Task { await activateSharePlay() }
        } label: {
            Label {
                Text("sharePlay.action", tableName: "Plinx")
            } icon: {
                Image(systemName: "shareplay")
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .plinxTVDetailActionSurface()
        .accessibilityLabel(Text("sharePlay.action", tableName: "Plinx"))
        .accessibilityIdentifier("media.detail.shareplay")
    }

    private var watchActionTitle: String {
        String(
            localized: viewModel.isWatched ? "quickActions.markUnwatched" : "quickActions.markWatched",
            table: "Plinx"
        )
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            seasonSelector
            if !viewModel.seasons.isEmpty {
                episodesRow
            }
        }
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingSeasons || viewModel.isLoading, viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("media.detail.loadingSeasons")
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.seasons) { season in
                        PlinxTVSeasonPillButton(
                            title: season.title,
                            isSelected: season.id == viewModel.selectedSeasonId,
                            onSelect: {
                                if season.id != viewModel.selectedSeasonId {
                                    hasUserSelectedSeason = true
                                }
                                Task { await viewModel.selectSeason(id: season.id) }
                            },
                            onFocus: { focusedMedia = season },
                            onBlur: {
                                if focusedMedia?.id == season.id {
                                    focusedMedia = nil
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private var episodesRow: some View {
        if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
            ProgressView("media.detail.loadingEpisodes")
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .foregroundStyle(.secondary)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 36) {
                        ForEach(viewModel.episodes) { episode in
                            PlinxTVEpisodeArtworkCard(
                                episode: episode,
                                imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                                runtime: viewModel.runtimeText(for: episode),
                                progress: viewModel.progressFraction(for: episode),
                                width: 460,
                                onPlay: { onPlay(episode.id, .episode) },
                                onFocus: { focusedMedia = episode }
                            )
                            .id(episode.id)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .task(id: viewModel.episodes.map(\.id)) {
                    await positionOnDeckEpisodeIfNeeded(using: scrollProxy)
                }
                .focusSection()
            }
        }
    }

    @MainActor
    private func positionOnDeckEpisodeIfNeeded(using scrollProxy: ScrollViewProxy) async {
        guard !hasHandledInitialEpisodePosition, !hasUserSelectedSeason else { return }
        hasHandledInitialEpisodePosition = true

        guard let primaryEpisodeID = viewModel.primaryActionItem?.id,
              viewModel.episodes.contains(where: { $0.id == primaryEpisodeID })
        else { return }

        await Task.yield()

        guard !Task.isCancelled,
              !hasUserSelectedSeason,
              viewModel.primaryActionItem?.id == primaryEpisodeID,
              viewModel.episodes.contains(where: { $0.id == primaryEpisodeID })
        else { return }

        scrollProxy.scrollTo(primaryEpisodeID, anchor: .leading)
    }

    private func handlePlay() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey(),
                  let playbackType = viewModel.primaryActionType
            else { return }

            if viewModel.shouldPlayPrimaryActionFromStart {
                onPlayFromStart(ratingKey, playbackType)
            } else {
                onPlay(ratingKey, playbackType)
            }
        }
    }

    private func handlePlayFromStart() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey(),
                  let playbackType = viewModel.primaryActionType
            else { return }
            onPlayFromStart(ratingKey, playbackType)
        }
    }

    private func activateSharePlay() async {
        guard let ratingKey = viewModel.primaryActionRatingKey,
              let playbackType = viewModel.primaryActionType,
              let item = viewModel.primaryActionItem
        else { return }

        await sharePlayCoordinator.activate(
            ratingKey: ratingKey,
            type: playbackType,
            title: item.primaryLabel,
            initialPosition: viewModel.primaryActionInitialPosition
        )
    }
}

private enum PlinxTVDetailActionMetrics {
    static let height: CGFloat = 82
    static let cornerRadius: CGFloat = 20
}

private extension View {
    func plinxTVDetailActionSurface(isPrimary: Bool = false) -> some View {
        background(
            RoundedRectangle(
                cornerRadius: PlinxTVDetailActionMetrics.cornerRadius,
                style: .continuous
            )
            .fill(PlinxBrand.surface.opacity(isPrimary ? 0.98 : 0.94))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: PlinxTVDetailActionMetrics.cornerRadius,
                style: .continuous
            )
            .stroke(Color.accentColor.opacity(isPrimary ? 0.48 : 0.32), lineWidth: 1)
        )
        .foregroundStyle(.white)
        .frame(height: PlinxTVDetailActionMetrics.height)
        .plinxTVFocusButton(
            style: PlinxFocusSurfaceStyle(
                focusedScale: 1,
                focusedShadowRadius: 18,
                cornerRadius: PlinxTVDetailActionMetrics.cornerRadius,
                focusedFillOpacity: 0.12
            )
        )
    }
}

private struct PlinxTVDetailPlayProgressIcon: View {
    let progress: Double?

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(Color.white.opacity(0.24), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Image(systemName: "play.fill")
                .font(.title3.weight(.semibold))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

private struct PlinxTVSeasonPillButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onFocus: () -> Void
    let onBlur: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .foregroundStyle(.white)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.48) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isFocused ? Color.accentColor : Color.white.opacity(0.22), lineWidth: isFocused ? 2.5 : 1.2)
            )
            .focusable()
            .focused($isFocused)
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { onFocus() } else { onBlur() }
            }
            .onPlayPauseCommand(perform: onSelect)
            .onTapGesture(perform: onSelect)
    }
}

private struct PlinxTVEpisodeArtworkCard: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let width: CGFloat
    let onPlay: () -> Void
    let onFocus: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        EpisodeArtworkView(
            episode: episode,
            imageURL: imageURL,
            width: width,
            runtime: runtime,
            progress: progress
        )
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.10 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused { onFocus() }
        }
        .onPlayPauseCommand(perform: onPlay)
        .onTapGesture(perform: onPlay)
    }
}
#endif
