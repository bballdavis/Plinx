import OSLog
import PlinxCore
import PlinxUI
import SwiftUI

/// Plinx-specific library detail screen.
///
/// This view owns all kid-safety, branding, and navigation chrome for the
/// library drill-down. The underlying Strimr sub-views (`LibraryBrowseView`,
/// `LibraryRecommendedView`, `LibraryCollectionsView`) are generic and kept
/// clean in the Strimr fork; Plinx injects behaviour via the seams those
/// views expose (`itemFilter`, `hubFilter`, `topContent`, `overrideLayout`,
/// `onLongPressMedia`).
struct PlinxLibraryDetailView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Plinx",
        category: "LibraryDetailSafety"
    )

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(\.dismiss) private var dismiss

    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }

    @State private var selectedTab: LibraryDetailTab = .recommended
    @State private var browseQuickSort: LibraryBrowseControlsViewModel.QuickSort = .newest
    @State private var browseRefreshIdentity = UUID()

    // MARK: - Body

    var body: some View {
        selectedTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(
                \.preferredLandscapeArtworkKind,
                ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library)
            )
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: settingsManager.interface.displayCollections) { _, displayCollections in
                if !displayCollections, selectedTab == .collections {
                    selectedTab = .recommended
                }
            }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .recommended:
            LibraryRecommendedView(
                viewModel: makeRecommendedViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                overrideLayout: { _ in preferredCarouselLayout }
            )
        case .browse:
            LibraryBrowseView(
                viewModel: makeBrowseViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                overrideLayout: preferredCarouselLayout,
                showsControls: false
            )
            .id(browseRefreshIdentity)
        case .collections:
            LibraryCollectionsView(
                viewModel: makeCollectionsViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent
            )
        case .playlists:
            EmptyView()
        }
    }

    // MARK: - Top content (scrolls with each tab's list)

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

                ZStack(alignment: .trailing) {
                    PlinxLibraryTabPicker(tabs: availableTabs, selectedTab: $selectedTab)
                        .frame(height: 76)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if selectedTab == .browse {
                        browseQuickSortButtons
                            .padding(.trailing, 2)
                    }
                }
            }
            .padding(.top, 4)
        )
    }

    // MARK: - Tab helpers

    private var availableTabs: [LibraryDetailTab] {
        LibraryDetailTab.allCases.filter { tab in
            switch tab {
            case .playlists:
                // Plinx: playlists surface is hidden — not suitable for the
                // primary kid-facing library tab.
                false
            case .collections:
                settingsManager.interface.displayCollections
            default:
                true
            }
        }
    }

    // MARK: - Layout heuristic

    /// Portrait (poster) for standard movie/TV libraries; landscape (letterbox)
    /// for "none"-agent libraries (YouTube, Home Videos) and clip libraries.
    private var preferredCarouselLayout: MediaCarousel.Layout? {
        LibraryCardLayoutPolicy.prefersLandscape(for: library) ? .landscape : nil
    }

    // MARK: - ViewModel factories (Plinx-side safety injection)

    private func makeRecommendedViewModel() -> LibraryRecommendedViewModel {
        let vm = LibraryRecommendedViewModel(library: library, context: plexApiContext)
        let policy = safetyPolicy
        vm.hubFilter = { hub in filterRecommendedHub(hub, policy: policy) }
        return vm
    }

    private func makeBrowseViewModel() -> LibraryBrowseViewModel {
        let vm = LibraryBrowseViewModel(
            library: library,
            context: plexApiContext,
            settingsManager: settingsManager
        )
        vm.controls.preferredQuickSort = browseQuickSort
        let policy = safetyPolicy
        let libType = library.type
        // None-agent libraries (YouTube Videos, Home Videos, etc.) are personally
        // curated and typically lack MPAA/TV content ratings. Allow unrated items
        // through while still respecting the rating ceiling for any item that does
        // carry an explicit rating (e.g., a TV-MA clip still gets blocked).
        let effectivePolicy = library.isNoneAgentLibrary
            ? SafetyPolicy.ratingOnly(maxMovie: policy.maxMovieRating, maxTV: policy.maxTVRating, allowUnrated: true)
            : policy
        vm.itemFilter = { item in
            if (libType == .movie || libType == .show), case .collection = item {
                return false
            }
            return StrimrAdapter.isAllowed(item, policy: effectivePolicy)
        }
        return vm
    }

    private var browseQuickSortButtons: some View {
        HStack(spacing: 8) {
            if selectedTab == .browse {
                quickSortButton(
                    iconName: "textformat.abc",
                    accessibilityID: "library.browse.sort.alphabetical",
                    quickSort: .alphabetical
                )

                quickSortButton(
                    iconName: "clock.arrow.circlepath",
                    accessibilityID: "library.browse.sort.new",
                    quickSort: .newest
                )
            }
        }
    }

    private func quickSortButton(
        iconName: String,
        accessibilityID: String,
        quickSort: LibraryBrowseControlsViewModel.QuickSort
    ) -> some View {
        let isSelected = browseQuickSort == quickSort

        return Button {
            guard browseQuickSort != quickSort else { return }
            browseQuickSort = quickSort
            browseRefreshIdentity = UUID()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.white.opacity(0.10))
                )
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    private func makeCollectionsViewModel() -> LibraryCollectionsViewModel {
        let vm = LibraryCollectionsViewModel(library: library, context: plexApiContext)
        let policy = safetyPolicy
        vm.itemFilter = { item in
            StrimrAdapter.isAllowed(item, policy: policy)
        }
        return vm
    }

    private func filterRecommendedHub(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        guard let safetyFiltered = StrimrAdapter.filtered(hub, policy: policy) else {
            Self.logger.debug(
                "Drop hub id=\(hub.id, privacy: .public) title=\(hub.title, privacy: .public) reason=safety_filter_empty"
            )
            return nil
        }
        if safetyFiltered.items.count != hub.items.count {
            Self.logger.debug(
                "Filtered hub id=\(hub.id, privacy: .public) title=\(hub.title, privacy: .public) before=\(hub.items.count) after=\(safetyFiltered.items.count)"
            )
        }
        return safetyFiltered
    }
}

// MARK: - LibraryDetailTab icon extension (Plinx augmentation)

extension LibraryDetailTab {
    /// SF Symbol name used by `PlinxLibraryTabPicker`.
    var plinxIconName: String {
        switch self {
        case .recommended: return "star.fill"
        case .browse:      return "square.grid.2x2.fill"
        case .collections: return "rectangle.stack.fill"
        case .playlists:   return "music.note.list"
        }
    }
}

// MARK: - Kids icon-button tab picker

/// Large, tap-friendly icon-button tab bar for library navigation.
///
/// Uses bigger buttons on iPad (`.regular` size class) and slightly smaller
/// buttons on iPhone (`.compact`) — both optimised for children's motor accuracy.
private struct PlinxLibraryTabPicker: View {
    let tabs: [LibraryDetailTab]
    @Binding var selectedTab: LibraryDetailTab

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }

    private var buttonMinWidth: CGFloat   { isRegular ? 108 : 82 }
    private var buttonHeight: CGFloat     { isRegular ? 66  : 52 }
    private var iconPointSize: CGFloat    { isRegular ? 26  : 19 }
    private var labelFont: Font           { isRegular ? .subheadline : .caption }
    private var cornerRadius: CGFloat     { isRegular ? 16  : 12 }
    private var hSpacing: CGFloat         { isRegular ? 12  : 8  }
    private var iconLabelSpacing: CGFloat { isRegular ? 8   : 5  }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: hSpacing) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
                .frame(minWidth: proxy.size.width - 32, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .frame(height: buttonHeight + 8)
        .accessibilityIdentifier("library.detail.tabPicker")
    }

    private func tabButton(_ tab: LibraryDetailTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: iconLabelSpacing) {
                Image(systemName: tab.plinxIconName)
                    .font(.system(size: iconPointSize, weight: .semibold))
                Text(tab.title)
                    .font(labelFont.bold())
                    .lineLimit(1)
            }
            .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.10))
            )
            .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : Color.white.opacity(0.15),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        .accessibilityIdentifier("library.detail.tab.\(tab.rawValue)")
    }
}
