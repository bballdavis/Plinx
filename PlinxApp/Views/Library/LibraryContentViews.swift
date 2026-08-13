import PlinxCore
import PlinxUI
import SwiftUI

#if !os(tvOS)
struct PlinxLibraryRecommendedContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy

    @State var viewModel: LibraryRecommendedViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void
    let topContent: AnyView
    let overrideLayout: (Hub) -> MediaCarousel.Layout?
    let onViewAllHub: (Hub) -> Void

    private let landscapeHubIdentifiers = ["inprogress"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topContent

                ForEach(viewModel.hubs) { hub in
                    if hub.hasItems {
                        PlinxLibraryHubSection(
                            title: hub.title,
                            onViewAll: hub.canOpenDetail ? { onViewAllHub(hub) } : nil
                        ) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .task {
            await PlinxLibraryRecommendationLoader.load(
                viewModel: viewModel,
                context: plexApiContext,
                settingsManager: settingsManager,
                policy: safetyPolicy
            )
        }
        .onAppear {
            Task {
                await PlinxLibraryRecommendationLoader.load(
                    viewModel: viewModel,
                    context: plexApiContext,
                    settingsManager: settingsManager,
                    policy: safetyPolicy,
                    refreshIfNeeded: true
                )
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await PlinxLibraryRecommendationLoader.load(
                    viewModel: viewModel,
                    context: plexApiContext,
                    settingsManager: settingsManager,
                    policy: safetyPolicy,
                    refreshIfNeeded: true
                )
            }
        }
    }

    private func carousel(for hub: Hub) -> some View {
        let resolvedLayout = layout(for: hub)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: carouselSpacing(for: resolvedLayout)) {
                ForEach(hub.items) { media in
                    recommendedCard(media, layout: resolvedLayout)
                }
            }
            .padding(.horizontal, 2)
        }
        .mouseDragScrolling()
    }

    private func carouselSpacing(for layout: MediaCarousel.Layout) -> CGFloat {
        switch layout {
        case .portrait: 12
        case .landscape: 16
        }
    }

    @ViewBuilder
    private func recommendedCard(_ media: MediaDisplayItem, layout: MediaCarousel.Layout) -> some View {
        switch layout {
        case .portrait:
            PlinxLibraryPortraitMediaCard(media: media, showsLabels: true) {
                onSelectMedia(media)
            }
            .plinxQuickActionLongPress { onLongPressMedia(media) }
        case .landscape:
            PlinxLibraryLandscapeMediaCard(media: media, showsLabels: true) {
                onSelectMedia(media)
            }
            .plinxQuickActionLongPress { onLongPressMedia(media) }
        }
    }

    private func layout(for hub: Hub) -> MediaCarousel.Layout {
        if let override = overrideLayout(hub) {
            return override
        }
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains(where: identifier.contains) ? .landscape : .portrait
    }
}

struct PlinxLibraryBrowseContentView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void
    let topContent: AnyView
    let overrideLayout: MediaCarousel.Layout?
    let showsControls: Bool

    private var usesLandscapeCards: Bool {
        guard let overrideLayout else { return false }
        if case .landscape = overrideLayout {
            return true
        }
        return false
    }

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 180 : 112
    }

    private var cardHeight: CGFloat? {
        usesLandscapeCards ? cardWidth * 9 / 16 : nil
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top)]
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topContent

                if showsControls, controls.hasDisplayTypes {
                    LibraryBrowseControlsView(
                        viewModel: controls,
                        showsBackButton: viewModel.canNavigateBack,
                        onNavigateBack: viewModel.navigateBack
                    )
                }

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(Array(viewModel.browseItems.enumerated()), id: \.element.id) { index, item in
                        browseCard(item)
                            .task {
                                if index == viewModel.browseItems.count - 1 {
                                    await viewModel.loadMore()
                                }
                            }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading, viewModel.browseItems.isEmpty {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.browse.loading",
                        table: "Plinx"
                    )
                )
            } else if let errorMessage = viewModel.errorMessage, viewModel.browseItems.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater")
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.browseItems.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description")
                )
            }
        }
        .task {
            await viewModel.load()
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
            FolderCard(
                title: folder.title,
                height: cardHeight,
                width: cardWidth,
                showsLabels: true
            ) {
                viewModel.enterFolder(folder)
            }
        }
    }
}

struct PlinxLibraryCollectionsContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State var viewModel: LibraryCollectionsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void
    let topContent: AnyView

    private let cardWidth: CGFloat = 112
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topContent

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(viewModel.items) { media in
                        PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                            onSelectMedia(media)
                        }
                        .plinxQuickActionLongPress { onLongPressMedia(media) }
                        .task {
                            if media == viewModel.items.last {
                                await viewModel.loadMore()
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading, viewModel.items.isEmpty {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.browse.loading",
                        table: "Plinx"
                    )
                )
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater")
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description")
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }
}
#endif
