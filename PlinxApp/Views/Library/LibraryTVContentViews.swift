import PlinxCore
import PlinxUI
import SwiftUI

#if os(tvOS)
struct PlinxLibraryRecommendedRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy

    @State var viewModel: LibraryRecommendedViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let landscapeHubIdentifiers: [String] = ["inprogress"]

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
                context: plexApiContext,
                settingsManager: settingsManager,
                policy: safetyPolicy
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
                onSelectMedia: onSelectMedia
            )
        } else {
            PlinxLibraryPortraitCarousel(
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        if usesLandscapeCards {
            return true
        }
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 32) {
                ForEach(items, id: \.id) { media in
                    PlinxLibraryLandscapeMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 32) {
                ForEach(items, id: \.id) { media in
                    PlinxLibraryPortraitMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
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
private struct PlinxLibraryBrowseControlsView: View {
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let showsBackButton: Bool
    let onNavigateBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if let panel = viewModel.activePanel {
                optionsRow(for: panel)
            }
        }
        .sheet(item: $viewModel.activeFilterSheet) { sheet in
            PlinxLibraryBrowseFilterSheetView(viewModel: viewModel, filter: sheet.filter)
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

                pill(
                    title: viewModel.typePillTitle,
                    systemImage: "square.grid.2x2",
                    isSelected: viewModel.activePanel == .type,
                    showsDisclosure: true
                ) {
                    viewModel.togglePanel(.type)
                }

                if viewModel.showsFilterPill {
                    pill(
                        title: viewModel.filterPillTitle,
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: viewModel.activePanel == .filters || !viewModel.selectedFilters.isEmpty,
                        showsDisclosure: true
                    ) {
                        viewModel.togglePanel(.filters)
                    }
                }

                if viewModel.showsSortPill {
                    pill(
                        title: viewModel.sortPillTitle,
                        systemImage: "arrow.up.arrow.down.circle",
                        isSelected: viewModel.activePanel == .sort || viewModel.selectedSort != nil,
                        showsDisclosure: true
                    ) {
                        viewModel.togglePanel(.sort)
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
    private func optionsRow(for panel: LibraryBrowseControlsViewModel.Panel) -> some View {
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
                case .filters:
                    ForEach(viewModel.availableFilters, id: \.filter) { filter in
                        let selection = viewModel.filterSelection(for: filter)
                        let isSelected = selection?.isEnabled == true
                        pill(
                            title: filterLabel(for: filter, selection: selection),
                            systemImage: isSelected ? "checkmark" : nil,
                            isSelected: isSelected,
                            showsDisclosure: !filter.isBoolean
                        ) {
                            viewModel.toggleFilter(filter)
                        }
                    }
                case .sort:
                    ForEach(viewModel.availableSorts, id: \.key) { sort in
                        let selection = viewModel.selectedSort
                        let isSelected = selection?.sort.key == sort.key
                        pill(
                            title: sort.title,
                            systemImage: sortDirectionImage(for: selection, sort: sort),
                            isSelected: isSelected
                        ) {
                            viewModel.toggleSort(sort)
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

    private func filterLabel(
        for filter: PlexSectionItemFilter,
        selection: LibraryBrowseControlsViewModel.FilterSelection?
    ) -> String {
        guard let option = selection?.selectedOption else { return filter.title }
        return filter.title + ": " + option.title
    }

    private func sortDirectionImage(
        for selection: LibraryBrowseControlsViewModel.SortSelection?,
        sort: PlexSectionItemSort
    ) -> String? {
        guard let selection, selection.sort.key == sort.key else { return nil }
        return selection.direction == .asc ? "arrow.up" : "arrow.down"
    }
}

private struct PlinxLibraryBrowseFilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let filter: PlexSectionItemFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Text(filter.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if viewModel.filterSelection(for: filter) != nil {
                    headerButton(title: String(localized: "library.browse.filters.clear")) {
                        viewModel.clearFilter(filter)
                        dismiss()
                    }
                }

                headerButton(title: String(localized: "common.actions.done")) {
                    dismiss()
                }
            }

            content
        }
        .padding(42)
        .background(Color.appBackground.ignoresSafeArea())
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingOptions(for: filter) {
            PlinxLoadingStateView(
                role: .content,
                label: LocalizedStringResource("library.browse.filters.loading")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.optionsError(for: filter) {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater")
            )
            .symbolRenderingMode(.multicolor)
        } else if viewModel.options(for: filter).isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.options(for: filter)) { option in
                        let isSelected = viewModel.filterSelection(for: filter)?.selectedOption?.id == option.id
                        Button {
                            viewModel.selectFilterOption(option, for: filter)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(.system(size: 26, weight: .semibold))
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 26, weight: .bold))
                                }
                            }
                        }
                        .buttonStyle(TvPillButtonStyle(isSelected: isSelected, cornerRadius: 18))
                        .focusEffectDisabled()
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func headerButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(TvPillButtonStyle(isSelected: false, cornerRadius: 18))
            .focusEffectDisabled()
    }
}

struct PlinxLibraryBrowseRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @FocusState private var focusedCharacterId: String?

    @State var viewModel: LibraryBrowseViewModel
    @State private var isPrefetchingCompleteCatalog = false
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onJumpToIndex: (Int) -> Void

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 320 : 200
    }

    private var cardHeight: CGFloat? {
        usesLandscapeCards ? (cardWidth / (16.0 / 9.0)) : nil
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 32)]
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                if controls.hasDisplayTypes {
                    PlinxLibraryBrowseControlsView(
                        viewModel: controls,
                        showsBackButton: viewModel.canNavigateBack,
                        onNavigateBack: viewModel.navigateBack
                    )
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
                    ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                        Group {
                            if let item = viewModel.itemsByIndex[index] {
                                switch item {
                                case let .media(media):
                                    if usesLandscapeCards {
                                        PlinxLibraryLandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                            onSelectMedia(media)
                                        }
                                    } else {
                                        PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                            onSelectMedia(media)
                                        }
                                    }
                                case let .folder(folder):
                                    FolderCard(title: folder.title, height: cardHeight, width: cardWidth, showsLabels: true) {
                                        viewModel.enterFolder(folder)
                                    }
                                }
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
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

            if viewModel.showsCharacterColumn {
                characterColumn(
                    characters: viewModel.sectionCharacters,
                    onSelect: { startIndex in
                        Task {
                            await viewModel.loadPagesAround(index: startIndex)
                            onJumpToIndex(startIndex)
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadCompleteFilteredCatalog()
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: viewModel.totalItemCount) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            guard !isLoading else { return }
            Task { await loadCompleteFilteredCatalog() }
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    /// Safety filtering happens client-side, so the upstream paged model only
    /// knows about the first allowed batch at initial load. Advance until the
    /// filtered count stops growing so Browse represents the complete library.
    private func loadCompleteFilteredCatalog() async {
        guard !isPrefetchingCompleteCatalog else { return }
        isPrefetchingCompleteCatalog = true
        defer { isPrefetchingCompleteCatalog = false }

        await viewModel.load()

        var previousCount: Int?
        for _ in 0 ..< 300 {
            guard !Task.isCancelled else { return }
            let currentCount = viewModel.totalItemCount
            guard previousCount != currentCount else { return }
            previousCount = currentCount
            await viewModel.loadPagesAround(index: max(currentCount - 1, 0))
            await Task.yield()
        }
    }

    private var defaultHeroMedia: MediaItem? {
        for index in 0 ..< viewModel.totalItemCount {
            if case let .media(media)? = viewModel.itemsByIndex[index],
               let playable = media.playableItem
            {
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

    private func characterColumn(
        characters: [LibraryBrowseViewModel.SectionCharacter],
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            ForEach(characters) { character in
                characterButton(
                    id: character.id,
                    title: character.title,
                    onTap: { onSelect(character.startIndex) }
                )
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
        .frame(width: 44, alignment: .top)
    }

    private func characterButton(id: String, title: String, onTap: @escaping () -> Void) -> some View {
        let isFocused = focusedCharacterId == id
        return Button {
            onTap()
        } label: {
            Text(title)
                .font(.caption2)
                .frame(width: 32, height: 32)
                .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedCharacterId, equals: id)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

struct PlinxLibraryCollectionsRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @FocusState private var focusedCharacterId: String?

    @State var viewModel: LibraryCollectionsViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onJumpToIndex: (Int) -> Void

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 320 : 200
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 32)]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
                    ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                        Group {
                            if let media = viewModel.itemsByIndex[index] {
                                if usesLandscapeCards {
                                    PlinxLibraryLandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                } else {
                                    PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                }
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
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

            characterColumn(
                characters: viewModel.sectionCharacters,
                onSelect: { startIndex in
                    Task {
                        await viewModel.loadPagesAround(index: startIndex)
                        onJumpToIndex(startIndex)
                    }
                }
            )
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

    private func characterColumn(
        characters: [LibraryCollectionsViewModel.SectionCharacter],
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            ForEach(characters) { character in
                characterButton(
                    id: character.id,
                    title: character.title,
                    onTap: { onSelect(character.startIndex) }
                )
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
        .frame(width: 44, alignment: .top)
    }

    private func characterButton(id: String, title: String, onTap: @escaping () -> Void) -> some View {
        let isFocused = focusedCharacterId == id
        return Button {
            onTap()
        } label: {
            Text(title)
                .font(.caption2)
                .frame(width: 32, height: 32)
                .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedCharacterId, equals: id)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
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

// MARK: - LibraryDetailTab icon extension (Plinx augmentation)
