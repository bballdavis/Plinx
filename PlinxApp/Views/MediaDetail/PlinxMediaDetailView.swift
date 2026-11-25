import Observation
import PlinxCore
import PlinxUI
import SwiftUI

/// Plinx media detail page.
///
/// The upstream `MediaDetailViewModel` loads everything through the screen's
/// `MediaServices`, which `SafeMediaServices` already filters fail-closed
/// (blocked titles throw, seasons, episodes, cast filmography, extras and
/// related hubs are filtered, management is denied while the parental gate is
/// locked). This view adds one last check of its own: the title it was opened
/// with must still pass `ContentSafetyGate`, so a card built under an older,
/// looser policy never shows its artwork or summary.
struct PlinxMediaDetailView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MediaDetailViewModel

    private let onPlay: (String, MediaKind) -> Void
    private let onPlayFromStart: (String, MediaKind) -> Void
    private let onShuffle: (String, MediaKind) -> Void
    private let onSelectRelated: (MediaDisplayItem) -> Void
    private let onSelectParentSeries: (PlayableMediaItem) -> Void
    private let onSelectPerson: ((Person) -> Void)?
    private let onRequestShellNavigationFocus: () -> Void
    private let contentFocusRequest: Int

    /// - Parameters:
    ///   - onPlayFromStart: Starts the title from the beginning. Defaults to `onPlay`.
    ///   - onSelectPerson: Opens a cast member's page. Defaults to the person route on the title's server.
    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, MediaKind) -> Void,
        onPlayFromStart: ((String, MediaKind) -> Void)? = nil,
        onShuffle: @escaping (String, MediaKind) -> Void,
        onSelectRelated: @escaping (MediaDisplayItem) -> Void,
        onSelectParentSeries: @escaping (PlayableMediaItem) -> Void = { _ in },
        onSelectPerson: ((Person) -> Void)? = nil,
        onRequestShellNavigationFocus: @escaping () -> Void = {},
        contentFocusRequest: Int = 0
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart ?? onPlay
        self.onShuffle = onShuffle
        self.onSelectRelated = onSelectRelated
        self.onSelectParentSeries = onSelectParentSeries
        self.onSelectPerson = onSelectPerson
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
        self.contentFocusRequest = contentFocusRequest
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isBlocked {
                blockedView
            } else {
                #if os(tvOS)
                PlinxMediaDetailTVView(
                    viewModel: viewModel,
                    onPlay: onPlay,
                    onPlayFromStart: onPlayFromStart,
                    onSelectMedia: onSelectRelated,
                    onSelectPerson: selectPerson,
                    onDismiss: { dismiss() },
                    onRequestShellNavigationFocus: onRequestShellNavigationFocus,
                    contentFocusRequest: contentFocusRequest
                )
                #else
                MediaDetailView(
                    viewModel: viewModel,
                    onPlay: onPlay,
                    onPlayFromStart: onPlayFromStart,
                    onShuffle: onShuffle,
                    onSelectMedia: onSelectRelated,
                    onSelectParentSeries: onSelectParentSeries,
                    onSelectPerson: selectPerson
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
        .onChange(of: contentPolicyRevision) { _, _ in
            // Content loaded under the previous policy is dropped, not merged.
            guard !isBlocked else { return }
            Task { await viewModel.loadDetails() }
        }
    }

    // MARK: - Safety

    private var contentPolicyRevision: Int {
        ContentSafetyGate.shared.revision
    }

    /// Fails closed: a title the current policy rejects, or any title other
    /// than the curated one during App Store capture, shows the blocked page.
    private var isBlocked: Bool {
        let gate = ContentSafetyGate.shared
        // Read so the page re-evaluates when the parent changes the policy.
        _ = gate.revision
        return !gate.isAllowed(viewModel.media.mediaItem)
            || !ReleaseScreenshotCaptureMode.allowsDetail(ratingKey: viewModel.media.id)
    }

    private func selectPerson(_ person: Person) {
        if let onSelectPerson {
            onSelectPerson(person)
        } else {
            coordinator.showPersonDetail(person, server: viewModel.server)
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
            #if os(tvOS)
            Button {
                dismiss()
            } label: {
                Label {
                    Text("common.actions.back", tableName: "Plinx")
                } icon: {
                    Image(systemName: "chevron.left")
                }
                .font(.headline.weight(.semibold))
            }
            .buttonStyle(TvPillButtonStyle(isSelected: false, cornerRadius: 16))
            .focusEffectDisabled()
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #endif
    }
}

#if os(tvOS)
/// Plinx-owned tvOS presentation for media detail.
///
/// The upstream `MediaDetailViewModel` owns loading, playback targets and
/// watch state; this shell supplies the television reading order, focus
/// behavior and backdrop treatment. It offers no Manage menu, file info,
/// playlist editing or track pickers: those are parent tools, and kids only
/// see Play, Play from start, Watched and Favorite. SharePlay appears only
/// when a parent-facing surface sets `sharePlayPresentationPolicy` to
/// `.enabled`.
private struct PlinxMediaDetailTVView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(\.sharePlayPresentationPolicy) private var sharePlayPresentationPolicy
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: MediaDetailViewModel
    @State private var focusedMedia: MediaItem?
    @State private var hasHandledInitialEpisodePosition = false
    @State private var hasUserSelectedSeason = false
    @State private var isSummaryExpanded = false
    @FocusState private var isBackFocused: Bool

    private let onPlay: (String, MediaKind) -> Void
    private let onPlayFromStart: (String, MediaKind) -> Void
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let onSelectPerson: (Person) -> Void
    private let onDismiss: () -> Void
    private let onRequestShellNavigationFocus: () -> Void
    private let contentFocusRequest: Int

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, MediaKind) -> Void,
        onPlayFromStart: @escaping (String, MediaKind) -> Void,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void,
        onSelectPerson: @escaping (Person) -> Void,
        onDismiss: @escaping () -> Void,
        onRequestShellNavigationFocus: @escaping () -> Void,
        contentFocusRequest: Int
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onSelectMedia = onSelectMedia
        self.onSelectPerson = onSelectPerson
        self.onDismiss = onDismiss
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
        self.contentFocusRequest = contentFocusRequest
    }

    private var spoilerProtection: SpoilerProtectionLevel {
        settingsManager.interface.spoilerProtection
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
            await bindableViewModel.loadDetailsIfNeeded()
        }
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            hasHandledInitialEpisodePosition = false
            hasUserSelectedSeason = false
            Task { await bindableViewModel.reloadAfterPlayback() }
        }
        .onChange(of: mediaServices.mediaRevision) { _, _ in
            guard !bindableViewModel.wasDeleted else {
                onDismiss()
                return
            }
            let changedMediaID = mediaServices.lastChangedMediaID
            Task { await bindableViewModel.refreshAfterMediaChange(itemID: changedMediaID) }
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
        .themeMusic(for: bindableViewModel.media.mediaItem)
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
            // The series logo stands in for its seasons and episodes, which have none of their own.
            TitleLogoView(
                media: viewModel.media.mediaItem,
                title: viewModel.detailPrimaryLabel(spoilerProtection: spoilerProtection),
                logoPath: viewModel.media.mediaItem.preferredLogoPath
                    ?? viewModel.parentSeries?.mediaItem.logoPath,
                maxSize: CGSize(width: 620, height: 170),
                alignment: .bottomLeading
            )
            .frame(maxWidth: 620, alignment: .leading)

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

    @ViewBuilder
    private var summarySection: some View {
        if viewModel.media.mediaItem.shouldHideSpoilerSummary(at: spoilerProtection) {
            Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        } else if let summary = viewModel.media.summary, !summary.isEmpty {
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
                        Text(isSummaryExpanded ? "common.actions.showLess" : "common.actions.readMore")
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

        if let favoriteActionErrorMessage = viewModel.favoriteActionErrorMessage {
            Label(favoriteActionErrorMessage, systemImage: "exclamationmark.octagon.fill")
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

            CastSection(viewModel: viewModel, onSelectPerson: onSelectPerson)
            ExtrasSection(viewModel: viewModel) { extra in
                onPlay(extra.id, .clip)
            }
            RelatedHubsSection(viewModel: viewModel, onSelectMedia: onSelectMedia)
        }
    }

    // MARK: - Actions

    private var actionStack: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                playButton

                if viewModel.shouldShowPlayFromStartButton {
                    playFromStartButton
                }

                watchToggleButton

                if viewModel.shouldShowFavoriteButton {
                    favoriteButton
                }
            }

            if sharePlayPresentationPolicy == .enabled {
                sharePlayButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The episode a series resumes and the time left, under the play title.
    private var primaryActionDetail: String? {
        let remaining = viewModel.primaryActionRemainingTime
        guard [.show, .season].contains(viewModel.media.type) else { return remaining }
        let parts = [viewModel.primaryActionItem?.tertiaryLabel, remaining].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
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
                    if let detail = primaryActionDetail, !detail.isEmpty {
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

    private var favoriteButton: some View {
        Button {
            Task { await viewModel.toggleFavoriteStatus() }
        } label: {
            if viewModel.isLoadingFavoriteStatus || viewModel.isUpdatingFavoriteStatus {
                ProgressView()
                    .tint(.white)
                    .frame(width: PlinxTVDetailActionMetrics.height, height: PlinxTVDetailActionMetrics.height)
            } else {
                Image(systemName: viewModel.favoriteActionIcon)
                    .font(.title2.weight(.semibold))
                    .frame(width: PlinxTVDetailActionMetrics.height, height: PlinxTVDetailActionMetrics.height)
            }
        }
        .plinxTVDetailActionSurface()
        .disabled(
            viewModel.isLoading
                || viewModel.isLoadingFavoriteStatus
                || viewModel.isUpdatingFavoriteStatus
        )
        .accessibilityLabel(Text(viewModel.favoriteActionTitle))
        .accessibilityIdentifier("media.detail.favorite")
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
        .disabled(sharePlayCoordinator.isActivating)
        .accessibilityLabel(Text("sharePlay.action", tableName: "Plinx"))
        .accessibilityIdentifier("media.detail.shareplay")
    }

    private var watchActionTitle: String {
        String(
            localized: viewModel.isWatched ? "quickActions.markUnwatched" : "quickActions.markWatched",
            table: "Plinx"
        )
    }

    // MARK: - Seasons and episodes

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
                                artworkPath: viewModel.artworkPath(
                                    for: episode,
                                    spoilerProtection: spoilerProtection
                                ),
                                title: episode.spoilerSafeTitle(at: spoilerProtection),
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
                .task(id: EpisodePositionTrigger(
                    episodeIDs: viewModel.episodes.map(\.id),
                    primaryEpisodeID: viewModel.primaryActionItem?.id,
                    isLoading: viewModel.isLoading
                )) {
                    await positionOnDeckEpisodeIfNeeded(using: scrollProxy)
                }
                .focusSection()
            }
        }
    }

    private struct EpisodePositionTrigger: Equatable {
        let episodeIDs: [String]
        let primaryEpisodeID: String?
        let isLoading: Bool
    }

    @MainActor
    private func positionOnDeckEpisodeIfNeeded(using scrollProxy: ScrollViewProxy) async {
        // Waits for the whole load: the next episode is resolved after the episodes are shown.
        guard !hasHandledInitialEpisodePosition, !hasUserSelectedSeason, !viewModel.isLoading else { return }
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

    // MARK: - Playback

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
        guard sharePlayPresentationPolicy == .enabled,
              let ratingKey = viewModel.primaryActionRatingKey,
              let playbackType = viewModel.primaryActionType,
              let item = viewModel.primaryActionItem
        else { return }

        await sharePlayCoordinator.activate(
            ratingKey: ratingKey,
            type: playbackType,
            title: item.primaryLabel,
            initialPosition: viewModel.primaryActionInitialPosition,
            server: viewModel.server
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
    let artworkPath: String?
    let title: String
    let runtime: String?
    let progress: Double?
    let width: CGFloat
    let onPlay: () -> Void
    let onFocus: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EpisodeArtworkView(
                episode: episode,
                artworkPath: artworkPath,
                width: width,
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

            caption
        }
        .frame(width: width, alignment: .leading)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(isFocused ? 0.82 : 0.56))
                    .lineLimit(1)
            }
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(isFocused ? 1 : 0.68))
                .lineLimit(1)
        }
        // Follows the focused artwork's lift so the scaled card never covers its caption.
        .offset(y: isFocused ? (width / (16 / 9)) * 0.05 : 0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var eyebrow: String? {
        let number = episode.index.map { String(localized: "media.detail.episodeNumber \($0)") }
        let parts = [number, runtime].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
#endif
