import PlinxUI
import SwiftUI

#if os(tvOS)
private enum PlinxCollectionFocusTarget: Hashable {
    case back
    case item(String)
}
#endif

/// Plinx collection page on the shared `CollectionDetailViewModel`.
///
/// Collections are containers: `SafeMediaServices` filters their entries one
/// by one, so the grid only ever holds titles the current policy allows.
struct PlinxCollectionDetailView: View {
    @State private var viewModel: CollectionDetailViewModel
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let onLongPressMedia: (MediaDisplayItem) -> Void
    private let onRequestShellNavigationFocus: () -> Void
    private let contentFocusRequest: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MediaServices.self) private var mediaServices
    @Environment(\.preferredLandscapeArtworkKind) private var preferredLandscapeArtworkKind
    #if os(tvOS)
    @FocusState private var focusedTarget: PlinxCollectionFocusTarget?
    @State private var contentFocusGeneration = 0
    #endif

    init(
        viewModel: CollectionDetailViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void,
        onLongPressMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onRequestShellNavigationFocus: @escaping () -> Void = {},
        contentFocusRequest: Int = 0
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onLongPressMedia = onLongPressMedia
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
        self.contentFocusRequest = contentFocusRequest
    }

    private var columns: [GridItem] {
        #if os(tvOS)
        if usesLandscapeCollectionGrid {
            [GridItem(.adaptive(minimum: 320, maximum: 340), spacing: 28)]
        } else {
            [GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 28)]
        }
        #else
        [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)]
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            contextRow
            #endif

            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    PlinxBrandedLoadingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    PlinxErrorView(message: error) {
                        Task { await viewModel.reload() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "common.empty.nothingToShow",
                        systemImage: "rectangle.stack",
                        description: Text("media.collection.empty", tableName: "Plinx")
                    )
                } else {
                    ScrollView {
                        if let years = viewModel.yearsText ?? viewModel.elementsCountText {
                            Text(years)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.items, id: \.id) { item in
                                collectionItem(item)
                            }
                        }
                        .padding(collectionGridPadding)
                    }
                }
            }
        }
        #if !os(tvOS)
        .navigationTitle(viewModel.collection.title)
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .onChange(of: ContentSafetyGate.shared.revision) { _, _ in
            // Entries listed under the previous policy are replaced, never merged.
            Task { await viewModel.reload() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
        #if os(tvOS)
        .onAppear {
            focusedTarget = .back
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: contentFocusRequest) { _, _ in
            restoreContentFocus(forceTransfer: true)
        }
        .onChange(of: viewModel.items.map(\.id)) { oldIDs, newIDs in
            guard case let .item(currentID) = focusedTarget else { return }
            let resolved = PlinxTVFocusCoordinator.resolvedContentID(
                currentID: currentID,
                previousIDs: oldIDs,
                availableIDs: newIDs
            )
            focusedTarget = resolved.map(PlinxCollectionFocusTarget.item) ?? .back
        }
        #else
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        #endif
    }

    private var collectionGridPadding: CGFloat {
        #if os(tvOS)
        36
        #else
        16
        #endif
    }

    private func artworkViewModel(for item: MediaDisplayItem) -> MediaImageViewModel {
        MediaImageViewModel(
            services: mediaServices,
            artworkKind: .thumb,
            media: item
        )
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
                    isFocused: focusedTarget == .back,
                    style: PlinxFocusSurfaceStyle(cornerRadius: 18)
                )
            }
            .buttonStyle(PlinkButtonStyle())
            .focusEffectDisabled()
            .focused($focusedTarget, equals: .back)
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    contentFocusGeneration &+= 1
                    onRequestShellNavigationFocus()
                case .down:
                    restoreContentFocus(preferFirstItem: true)
                default:
                    break
                }
            }

            Text(viewModel.collection.title)
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

    private var usesLandscapeCollectionGrid: Bool {
        preferredLandscapeArtworkKind != nil || viewModel.items.contains { $0.type == .clip }
    }

    private func usesLandscapeCard(for item: MediaDisplayItem) -> Bool {
        preferredLandscapeArtworkKind != nil || item.type == .clip
    }
    #endif

    @ViewBuilder
    private func collectionItem(_ item: MediaDisplayItem) -> some View {
        #if os(tvOS)
        let isFocused = focusedTarget == .item(item.id)
        let aspectRatio = usesLandscapeCard(for: item) ? (16.0 / 9.0) : (2.0 / 3.0)
        Button {
            onSelectMedia(item)
        } label: {
            MediaImageView(viewModel: artworkViewModel(for: item))
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .plinxFocusSurface(
                    isSelected: false,
                    isFocused: isFocused,
                    style: PlinxFocusSurfaceStyle(cornerRadius: 14)
                )
        }
        .buttonStyle(PlinkButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTarget, equals: .item(item.id))
        .onMoveCommand { direction in
            guard direction == .up,
                  item.id == viewModel.items.first?.id else { return }
            focusedTarget = .back
        }
        .plinxQuickActionLongPress {
            onLongPressMedia(item)
        }
        .accessibilityLabel(Text(item.primaryLabel))
        #else
        MediaImageView(viewModel: artworkViewModel(for: item))
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .plinxMediaCardInteraction(
                onTap: { onSelectMedia(item) },
                onLongPress: { onLongPressMedia(item) }
            )
            .accessibilityLabel(Text(item.primaryLabel))
        #endif
    }

    #if os(tvOS)
    private func restoreContentFocus(
        preferFirstItem: Bool = false,
        forceTransfer: Bool = false
    ) {
        let ids = viewModel.items.map(\.id)
        let currentID: String?
        if case let .item(id) = focusedTarget {
            currentID = id
        } else {
            currentID = nil
        }
        let resolved = PlinxTVFocusCoordinator.resolvedContentID(
            currentID: preferFirstItem ? nil : currentID,
            availableIDs: ids
        )
        let target = resolved.map(PlinxCollectionFocusTarget.item) ?? .back
        guard forceTransfer else {
            focusedTarget = target
            return
        }

        contentFocusGeneration &+= 1
        let generation = contentFocusGeneration
        focusedTarget = nil
        Task { @MainActor in
            await Task.yield()
            guard generation == contentFocusGeneration else { return }
            focusedTarget = target
        }
    }
    #endif
}
