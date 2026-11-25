import PlinxCore
import PlinxUI
import SwiftUI

/// Plinx-specific library detail screen.
///
/// Plinx owns the branding, layout and navigation chrome of the library
/// drill-down. The upstream library view models supply the content through the
/// screen's `MediaServices` (provided by `ServerScopedView`), which
/// `SafeMediaServices` has already filtered against the parent's policy.
struct PlinxLibraryDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    #if os(tvOS)
    @Environment(MediaFocusModel.self) private var mediaFocusModel
    @EnvironmentObject private var tvFocusCoordinator: PlinxTVFocusCoordinator
    #endif

    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var onRequestShellNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0

    /// The tab the child picked on this visit; `nil` shows the library's default tab.
    @State private var chosenTab: LibraryDetailTab?
    @State private var browseSession = LibraryBrowseSession()
    #if os(tvOS)
    @State private var tvHeroMedia: MediaItem?
    @FocusState private var focusedLibraryFilterTab: LibraryDetailTab?
    @State private var contentFocusGeneration = 0
    #endif

    // MARK: - Body

    var body: some View {
        Group {
            #if os(tvOS)
            tvSharedLayout
            #else
            selectedTabContent
                // A new content policy rebuilds the tab, so nothing loaded under the old one stays on screen.
                .id(ContentSafetyGate.shared.revision)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(
            \.preferredLandscapeArtworkKind,
            ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library)
        )
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        #if os(tvOS)
        .onChange(of: selectedTab) { _, newTab in
            focusedLibraryFilterTab = newTab
            mediaFocusModel.focusedMedia = nil
            tvHeroMedia = nil
        }
        .onAppear {
            tvFocusCoordinator.activate(.libraryDetail)
            focusedLibraryFilterTab = selectedTab
        }
        .onDisappear {
            // Tab selection updates focus ownership before this view leaves.
            // Only restore the Library root when this detail still owns it.
            guard tvFocusCoordinator.activeContentRegion == .libraryDetail else { return }
            tvFocusCoordinator.activate(.library)
        }
        .onChange(of: contentFocusRequest) { _, _ in
            let target = availableTabs.contains(selectedTab)
                ? selectedTab
                : availableTabs.first
            contentFocusGeneration &+= 1
            let generation = contentFocusGeneration
            focusedLibraryFilterTab = nil
            guard let target else { return }
            Task { @MainActor in
                await Task.yield()
                guard generation == contentFocusGeneration else { return }
                focusedLibraryFilterTab = target
            }
        }
        .onExitCommand {
            dismiss()
        }
        #endif
    }

    // MARK: - Tabs

    /// Upstream's tabs for this library and provider. Playlists have no
    /// kid-facing surface in Plinx, so that tab is never offered.
    private var availableTabs: [LibraryDetailTab] {
        LibraryDetailTab.available(
            for: library,
            provider: mediaServices.provider,
            displaysCollections: settingsManager.interface.displayCollections,
            displaysPlaylists: false
        )
    }

    /// Falls back to the default tab when the chosen one has since been hidden in settings.
    private var selectedTab: LibraryDetailTab {
        LibraryDetailTab.resolved(saved: chosenTab, available: availableTabs, library: library)
    }

    private var selectedTabBinding: Binding<LibraryDetailTab> {
        Binding { selectedTab } set: { chosenTab = $0 }
    }

    // MARK: - View models

    private func makeRecommendedViewModel() -> LibraryRecommendedViewModel {
        LibraryRecommendedViewModel(library: library, services: mediaServices, settingsManager: settingsManager)
    }

    private func makeBrowseViewModel() -> LibraryBrowseViewModel {
        LibraryBrowseViewModel(
            library: library,
            services: mediaServices,
            settingsManager: settingsManager,
            browseSession: browseSession
        )
    }

    private func usesLandscapeCards(on surface: LibraryCardLayoutPolicy.DetailSurface) -> Bool {
        LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: surface)
    }

    // MARK: - iOS

    #if !os(tvOS)
    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .recommended:
            PlinxLibraryRecommendedContentView(
                viewModel: makeRecommendedViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                overrideLayout: { _ in preferredCarouselLayout },
                onViewAllHub: { hub in
                    mainCoordinator.showHubDetail(hub)
                }
            )
        case .browse:
            PlinxLibraryBrowseContentView(
                viewModel: makeBrowseViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                usesLandscapeCards: usesLandscapeCards(on: .browse)
            )
        case .collections:
            PlinxLibraryCollectionsContentView(
                viewModel: LibraryCollectionsViewModel(library: library, services: mediaServices),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent
            )
        case .playlists:
            EmptyView()
        }
    }

    /// Scrolls with each tab's list.
    private var scrollingTopContent: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PlinxChromeButton(systemImage: "chevron.left") {
                        dismiss()
                    }

                    Text(library.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                if availableTabs.count > 1 {
                    PlinxLibraryTabPicker(tabs: availableTabs, selectedTab: selectedTabBinding)
                        .frame(height: 76)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.top, 4)
        )
    }

    /// Portrait (poster) for standard movie/TV libraries; landscape (letterbox)
    /// for "none"-agent libraries (YouTube, Home Videos) and clip libraries.
    private var preferredCarouselLayout: MediaCarousel.Layout? {
        LibraryCardLayoutPolicy.prefersLandscape(for: library) ? .landscape : nil
    }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
    private var tvSharedLayout: some View {
        SharedTvBrowsePageLayout(
            heroMedia: mediaFocusModel.focusedMedia ?? tvHeroMedia,
            // Always shown, even with one tab: the shell routes focus into this row.
            showsFilters: true,
            navigationContent: {
                EmptyView()
            },
            filterContent: {
                tvFilterRow
            },
            rowsContent: { _ in
                tvRowsContent
                    // A new content policy rebuilds the rows, so nothing loaded under the old one stays on screen.
                    .id(ContentSafetyGate.shared.revision)
            }
        )
    }

    @ViewBuilder
    private var tvRowsContent: some View {
        switch selectedTab {
        case .recommended:
            PlinxLibraryRecommendedRowsView(
                viewModel: makeRecommendedViewModel(),
                heroMedia: $tvHeroMedia,
                usesLandscapeCards: usesLandscapeCards(on: .recommended),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia
            )
            .padding(.horizontal, TvBrowseHeroMetrics.alignedContentInset)
            .padding(.bottom, 28)
        case .browse:
            PlinxLibraryBrowseRowsView(
                viewModel: makeBrowseViewModel(),
                heroMedia: $tvHeroMedia,
                usesLandscapeCards: usesLandscapeCards(on: .browse),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia
            )
            .padding(.horizontal, TvBrowseHeroMetrics.alignedContentInset)
            .padding(.bottom, 28)
        case .collections:
            PlinxLibraryCollectionsRowsView(
                viewModel: LibraryCollectionsViewModel(
                    library: library,
                    services: mediaServices,
                    settingsManager: settingsManager
                ),
                heroMedia: $tvHeroMedia,
                usesLandscapeCards: usesLandscapeCards(on: .collections),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia
            )
            .padding(.horizontal, TvBrowseHeroMetrics.alignedContentInset)
            .padding(.bottom, 28)
        case .playlists:
            EmptyView()
        }
    }

    private var tvFilterRow: some View {
        HStack(spacing: 12) {
            ForEach(availableTabs) { tab in
                tvFilterButton(tab: tab)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func tvFilterButton(tab: LibraryDetailTab) -> some View {
        Button {
            chosenTab = tab
            focusedLibraryFilterTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.plinxIconName)
                    .font(.subheadline.weight(.semibold))
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .focused($focusedLibraryFilterTab, equals: tab)
        .buttonStyle(TvPillButtonStyle(isSelected: selectedTab == tab))
        .focusEffectDisabled()
        .accessibilityIdentifier("library.detail.filter.\(tab.rawValue)")
        .onMoveCommand { direction in
            guard direction == .up else { return }
            contentFocusGeneration &+= 1
            onRequestShellNavigationFocus()
        }
    }
    #endif
}
