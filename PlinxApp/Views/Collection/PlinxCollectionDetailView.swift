import SwiftUI
import PlinxUI

struct PlinxCollectionDetailView: View {
    @State var viewModel: SafeCollectionDetailViewModel
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }

    @Environment(PlexAPIContext.self) private var plexApiContext
    #if os(tvOS)
    @FocusState private var focusedItemID: String?
    #endif

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 28)]
        #else
        [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)]
        #endif
    }

    var body: some View {
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
        .navigationTitle(viewModel.collection.title)
        #if os(tvOS)
        .toolbarTitleDisplayMode(.inline)
        #else
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    private var collectionGridPadding: CGFloat {
        #if os(tvOS)
        36
        #else
        16
        #endif
    }

    @ViewBuilder
    private func collectionItem(_ item: MediaDisplayItem) -> some View {
        #if os(tvOS)
        let isFocused = focusedItemID == item.id
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
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isFocused ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 3)
            )
            .shadow(color: isFocused ? Color.accentColor.opacity(0.65) : .clear, radius: isFocused ? 22 : 0)
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($focusedItemID, equals: item.id)
        .onLongPressGesture {
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
        .onTapGesture { onSelectMedia(item) }
        .onLongPressGesture { onLongPressMedia(item) }
        #endif
    }
}
