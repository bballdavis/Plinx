import SwiftUI
import PlinxUI

#if os(tvOS)
private enum PlinxCollectionFocusTarget: Hashable {
    case back
    case item(String)
}
#endif

struct PlinxCollectionDetailView: View {
    @State var viewModel: SafeCollectionDetailViewModel
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var onRequestShellNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(\.preferredLandscapeArtworkKind) private var preferredLandscapeArtworkKind
    #if os(tvOS)
    @FocusState private var focusedTarget: PlinxCollectionFocusTarget?
    @State private var previousItemIDs: [String] = []
    #endif

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
                        Task { await viewModel.load() }
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
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
        #if os(tvOS)
        .onAppear {
            previousItemIDs = viewModel.items.map(\.id)
            focusedTarget = .back
        }
        .onChange(of: contentFocusRequest) { _, _ in
            restoreContentFocus()
        }
        .onChange(of: viewModel.items.map(\.id)) { oldIDs, newIDs in
            defer { previousItemIDs = newIDs }
            guard case let .item(currentID) = focusedTarget else { return }
            let resolved = PlinxTVFocusCoordinator.resolvedContentID(
                currentID: currentID,
                previousIDs: oldIDs,
                availableIDs: newIDs
            )
            focusedTarget = resolved.map(PlinxCollectionFocusTarget.item) ?? .back
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
                    focusedTarget = nil
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
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: .thumb,
                    media: item
                )
            )
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
        #else
        MediaImageView(
            viewModel: MediaImageViewModel(
                context: plexApiContext,
                artworkKind: .thumb,
                media: item
            )
        )
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .plinxMediaCardInteraction(
            onTap: { onSelectMedia(item) },
            onLongPress: { onLongPressMedia(item) }
        )
        #endif
    }

    #if os(tvOS)
    private func restoreContentFocus(preferFirstItem: Bool = false) {
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
        focusedTarget = resolved.map(PlinxCollectionFocusTarget.item) ?? .back
    }
    #endif
}
