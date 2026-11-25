import PlinxCore
import PlinxUI
import SwiftUI

#if os(tvOS)
struct PlinxLibraryRecommendedRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager

    @State var viewModel: LibraryRecommendedViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(viewModel.hubs) { hub in
                if hub.hasItems {
                    PlinxLibraryHubSection(title: hub.title) {
                        carousel(for: hub)
                    }
                }
            }

            if viewModel.isLoading, !viewModel.hasContent {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.recommended.loading",
                        table: "Plinx"
                    )
                )
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if !viewModel.hasContent, !viewModel.isLoading {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await PlinxLibraryRecommendationLoader.load(
                viewModel: viewModel,
                services: mediaServices,
                settingsManager: settingsManager
            )
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: viewModel.hubs.count) { _, _ in
            updateHeroMedia()
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            PlinxLibraryLandscapeCarousel(
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia
            )
        } else {
            PlinxLibraryPortraitCarousel(
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        if usesLandscapeCards {
            return true
        }
        let identifier = hub.id.lowercased()
        return PlinxLibraryRecommendationLoader.landscapeHubIdentifiers.contains { identifier.contains($0) }
    }

    private var defaultHeroMedia: MediaItem? {
        for hub in viewModel.hubs where hub.hasItems {
            if let item = hub.items.compactMap(\.playableItem).first {
                return item
            }
        }
        return nil
    }

    private func updateHeroMedia() {
        if let focused = focusModel.focusedMedia {
            if heroMedia?.id != focused.id {
                heroMedia = focused
            }
            return
        }

        if heroMedia == nil {
            heroMedia = defaultHeroMedia
        }
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil else { return }
        if let initial = heroMedia ?? defaultHeroMedia {
            focusModel.focusedMedia = initial
        }
    }
}

private struct PlinxLibraryLandscapeCarousel: View {
    let items: [MediaDisplayItem]
    let showsLabels: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 32) {
                ForEach(items, id: \.id) { media in
                    PlinxLibraryLandscapeMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
                    .plinxQuickActionLongPress { onLongPressMedia(media) }
                }
            }
            .padding(.vertical, 20)
            .padding(.trailing, 16)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }
}

private struct PlinxLibraryPortraitCarousel: View {
    let items: [MediaDisplayItem]
    let showsLabels: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 32) {
                ForEach(items, id: \.id) { media in
                    PlinxLibraryPortraitMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
                    .plinxQuickActionLongPress { onLongPressMedia(media) }
                }
            }
            .padding(.vertical, 16)
            .padding(.trailing, 16)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }
}

/// Plinx-owned browse controls keep all library filters on the shared dark
/// focus treatment instead of allowing tvOS to add its bright white plate.
/// Type and sort open an inline row of pills; filters open the upstream
/// filter form, which covers both Plex and Jellyfin libraries.
private struct PlinxLibraryBrowseControlsView: View {
    private enum Panel {
        case type
        case sort
    }

    let viewModel: LibraryBrowseControlsViewModel
    let showsBackButton: Bool
    let onNavigateBack: () -> Void

    @State private var activePanel: Panel?
    @State private var isFiltersPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if let activePanel {
                optionsRow(for: activePanel)
            }
        }
        .sheet(isPresented: $isFiltersPresented) {
            LibraryBrowseFiltersView(
                viewModel: viewModel,
                serverFilters: .available,
                canReset: viewModel.canResetSelection,
                onReset: viewModel.resetSelection,
                onDone: { isFiltersPresented = false }
            )
        }
    }

    private var topRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                if showsBackButton {
                    pill(
                        title: String(localized: "library.browse.folders.back"),
                        systemImage: "chevron.left",
                        isSelected: false,
                        action: onNavigateBack
                    )
                }

                if viewModel.hasDisplayTypes {
                    pill(
                        title: viewModel.typeTitle,
                        systemImage: "square.grid.2x2",
                        isSelected: activePanel == .type,
                        showsDisclosure: true
                    ) {
                        togglePanel(.type)
                    }
                }

                if viewModel.hasControls, viewModel.showsFilterControl {
                    pill(
                        title: filtersTitle,
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: viewModel.hasActiveFilters
                    ) {
                        activePanel = nil
                        isFiltersPresented = true
                    }
                }

                if viewModel.hasControls, viewModel.showsSortControl {
                    pill(
                        title: viewModel.selectedSortTitle ?? String(localized: "library.browse.sort.title"),
                        systemImage: sortImage,
                        isSelected: activePanel == .sort,
                        showsDisclosure: true
                    ) {
                        togglePanel(.sort)
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }

    @ViewBuilder
    private func optionsRow(for panel: Panel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                switch panel {
                case .type:
                    ForEach(viewModel.displayTypes) { type in
                        pill(
                            title: type.title,
                            systemImage: nil,
                            isSelected: type.key == viewModel.selectedDisplayType?.key
                        ) {
                            viewModel.selectDisplayType(type)
                        }
                    }
                case .sort:
                    ForEach(viewModel.sortChoices) { choice in
                        let isSelected = choice.id == viewModel.selectedSortID
                        pill(
                            title: choice.title,
                            systemImage: isSelected ? sortImage : nil,
                            isSelected: isSelected
                        ) {
                            if isSelected {
                                viewModel.setSortAscending(!(viewModel.isSortAscending ?? true))
                            } else {
                                viewModel.selectSort(id: choice.id)
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }

    private func togglePanel(_ panel: Panel) {
        activePanel = activePanel == panel ? nil : panel
    }

    private var filtersTitle: String {
        let title = String(localized: "library.browse.filters.title")
        let count = viewModel.activeFilters.count
        return count > 0 ? "\(title) · \(count)" : title
    }

    private var sortImage: String {
        switch viewModel.isSortAscending {
        case true?: "arrow.up"
        case false?: "arrow.down"
        case nil: "arrow.up.arrow.down.circle"
        }
    }

    private func pill(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        showsDisclosure: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if showsDisclosure {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .opacity(0.72)
                }
            }
        }
        .buttonStyle(TvPillButtonStyle(isSelected: isSelected, cornerRadius: 18))
        .focusEffectDisabled()
    }
}

struct PlinxLibraryBrowseRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(MediaServices.self) private var mediaServices: MediaServices?

    @State var viewModel: LibraryBrowseViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 320 : 200
    }

    private var cardHeight: CGFloat? {
        usesLandscapeCards ? (cardWidth / (16.0 / 9.0)) : nil
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 32)]
    }

    private var currentListing: PlinxLibraryBrowseListing {
        PlinxLibraryBrowseListing(
            itemsByIndex: viewModel.itemsByIndex,
            totalItemCount: viewModel.totalItemCount,
            library: viewModel.library
        )
    }

    var body: some View {
        let listing = currentListing

        VStack(alignment: .leading, spacing: 14) {
            if viewModel.controls.hasControls || viewModel.canNavigateBack {
                PlinxLibraryBrowseControlsView(
                    viewModel: viewModel.controls,
                    showsBackButton: viewModel.canNavigateBack,
                    onNavigateBack: viewModel.navigateBack
                )
            }

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
                ForEach(listing.items) { item in
                    browseCard(item)
                }

                if let nextIndex = listing.nextIndex {
                    PlinxLibraryCardPlaceholder(width: cardWidth, usesLandscapeCard: usesLandscapeCards)
                        .task(id: nextIndex) {
                            viewModel.itemAppeared(at: nextIndex)
                        }
                }
            }

            if viewModel.isLoading, listing.items.isEmpty {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.browse.loading",
                        table: "Plinx"
                    )
                )
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = viewModel.errorMessage, listing.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater")
                )
                .symbolRenderingMode(.multicolor)
            } else if listing.items.isEmpty, listing.nextIndex == nil, !viewModel.isLoading {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // Plinx has no folder-tree view; a tree saved on this device falls back to the grid.
            if viewModel.isFolderTreeActive {
                viewModel.toggleFolderTree()
            } else {
                await viewModel.load()
            }
        }
        .onChange(of: mediaServices?.deletedMediaIDs) { _, deletedIDs in
            viewModel.removeDeletedItems(ids: deletedIDs ?? [])
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: viewModel.itemsByIndex.count) { _, _ in
            updateHeroMedia()
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    @ViewBuilder
    private func browseCard(_ item: LibraryBrowseItem) -> some View {
        switch item {
        case let .media(media):
            if usesLandscapeCards {
                PlinxLibraryLandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                    onSelectMedia(media)
                }
                .plinxQuickActionLongPress { onLongPressMedia(media) }
            } else {
                PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                    onSelectMedia(media)
                }
                .plinxQuickActionLongPress { onLongPressMedia(media) }
            }
        case let .folder(folder):
            FolderCard(title: folder.title, height: cardHeight, width: cardWidth, showsLabels: true) {
                viewModel.enterFolder(folder)
            }
        }
    }

    private var defaultHeroMedia: MediaItem? {
        for item in currentListing.items {
            if case let .media(media) = item, let playable = media.playableItem {
                return playable
            }
        }
        return nil
    }

    private func updateHeroMedia() {
        if let focused = focusModel.focusedMedia {
            if heroMedia?.id != focused.id {
                heroMedia = focused
            }
            return
        }

        if heroMedia == nil {
            heroMedia = defaultHeroMedia
        }
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil else { return }
        if let initial = heroMedia ?? defaultHeroMedia {
            focusModel.focusedMedia = initial
        }
    }
}

struct PlinxLibraryCollectionsRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel

    @State var viewModel: LibraryCollectionsViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 320 : 200
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 32)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
                ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                    Group {
                        if let media = viewModel.itemsByIndex[index] {
                            if usesLandscapeCards {
                                PlinxLibraryLandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                    onSelectMedia(media)
                                }
                                .plinxQuickActionLongPress { onLongPressMedia(media) }
                            } else {
                                PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                    onSelectMedia(media)
                                }
                                .plinxQuickActionLongPress { onLongPressMedia(media) }
                            }
                        } else {
                            PlinxLibraryCardPlaceholder(width: cardWidth, usesLandscapeCard: usesLandscapeCards)
                        }
                    }
                    .id(index)
                    .onAppear {
                        Task {
                            await viewModel.loadPagesAround(index: index)
                        }
                    }
                }
            }

            if viewModel.isLoading, viewModel.itemsByIndex.isEmpty {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.browse.loading",
                        table: "Plinx"
                    )
                )
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.itemsByIndex.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater")
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.totalItemCount == 0, !viewModel.isLoading {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.load()
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    private var defaultHeroMedia: MediaItem? {
        for index in 0 ..< viewModel.totalItemCount {
            if let media = viewModel.itemsByIndex[index], let playable = media.playableItem {
                return playable
            }
        }
        return nil
    }

    private func updateHeroMedia() {
        if let focused = focusModel.focusedMedia {
            if heroMedia?.id != focused.id {
                heroMedia = focused
            }
            return
        }

        if heroMedia == nil {
            heroMedia = defaultHeroMedia
        }
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil else { return }
        if let initial = heroMedia ?? defaultHeroMedia {
            focusModel.focusedMedia = initial
        }
    }
}
#endif
