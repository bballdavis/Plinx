import SwiftUI
import PlinxUI

struct PlinxCollectionDetailView: View {
    @State var viewModel: SafeCollectionDetailViewModel
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }

    @Environment(PlexAPIContext.self) private var plexApiContext

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

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
                            MediaImageView(
                                viewModel: MediaImageViewModel(
                                    context: plexApiContext,
                                    artworkKind: .thumb,
                                    media: item
                                )
                            )
                            .aspectRatio(2/3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectMedia(item) }
                            .onLongPressGesture { onLongPressMedia(item) }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(viewModel.collection.title)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }
}
