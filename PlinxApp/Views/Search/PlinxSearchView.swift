import SwiftUI
import PlinxUI

struct PlinxSearchView: View {
    @State var viewModel: SafeSearchViewModel
    var onSelectMedia: (MediaDisplayItem) -> Void

    @Environment(PlexAPIContext.self) private var plexApiContext
    @FocusState private var searchFocused: Bool
    @Environment(\.safetyPolicy) private var safetyPolicy

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().opacity(0.2)

            resultsContent
        }
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            TextField(text: $viewModel.query) {
                    Text("search.placeholder", tableName: "Plinx")
                }
                .font(.body)
                .foregroundStyle(.white)
                .tint(.orange)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { viewModel.submitSearch() }
                .onChange(of: viewModel.query) { _, _ in viewModel.queryDidChange() }

            if !viewModel.query.isEmpty {
                Button(action: viewModel.clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.system(size: 18))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        if viewModel.query.isEmpty {
            emptyPrompt
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(.orange)
        } else if viewModel.items.isEmpty {
            Text("search.no_results \(viewModel.query)", tableName: "Plinx")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            resultsList
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.orange.opacity(0.7))
            Text("search.placeholder.prompt", tableName: "Plinx")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    Button { onSelectMedia(item) } label: {
                        resultRow(item)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 76)
                        .opacity(0.15)
                }
            }
            .padding(.bottom, 120)
        }
    }

    private func resultRow(_ item: MediaDisplayItem) -> some View {
        HStack(spacing: 14) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: .thumb,
                    media: item
                )
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.primaryLabel)
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let sub = item.secondaryLabel {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                if let rating = item.playableItem?.contentRating {
                    Text(rating)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.8)))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
