import SwiftUI
import PlinxUI

struct PlinxSearchView: View {
    @State var viewModel: SafeSearchViewModel
    var topContent: AnyView? = nil
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }

    @Environment(PlexAPIContext.self) private var plexApiContext
    @FocusState private var searchFocused: Bool
    @Environment(\.safetyPolicy) private var safetyPolicy

    private var searchAccentColor: Color { PlinxAccentColor.green.color }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let topContent {
                    topContent
                }

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider().opacity(0.2)

                resultsContent
                    .padding(.top, 12)
            }
            .padding(.bottom, 120)
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
                .foregroundStyle(searchAccentColor)

            TextField(text: $viewModel.query) {
                    Text("search.placeholder", tableName: "Plinx")
                }
                .font(.body)
                .foregroundStyle(.white)
                .tint(searchAccentColor)
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
        } else if viewModel.shouldShowTypingPrompt {
            liveSearchPrompt
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .tint(searchAccentColor)
        } else if viewModel.items.isEmpty {
            Text("search.no_results \(viewModel.query)", tableName: "Plinx")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else {
            resultsList
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(searchAccentColor.opacity(0.7))
            Text("search.placeholder.prompt", tableName: "Plinx")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private var liveSearchPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(searchAccentColor.opacity(0.7))
            Text("search.live.minimum \(Int64(viewModel.remainingCharactersForLiveSearch))", tableName: "Plinx")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private var resultsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.items) { item in
                resultRow(item)
                    .onTapGesture { onSelectMedia(item) }
                    .onLongPressGesture { onLongPressMedia(item) }

                Divider()
                    .padding(.leading, 76)
                    .opacity(0.15)
            }
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
