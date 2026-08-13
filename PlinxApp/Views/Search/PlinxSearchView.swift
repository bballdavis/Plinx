import SwiftUI
import PlinxUI

struct PlinxSearchView: View {
    @State var viewModel: SafeSearchViewModel
    var topContent: AnyView? = nil
    var onRequestShellNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }

    @Environment(PlexAPIContext.self) private var plexApiContext
    @FocusState private var searchFocused: Bool
    #if os(tvOS)
    @EnvironmentObject private var tvFocusCoordinator: PlinxTVFocusCoordinator
    @FocusState private var focusedResultID: String?
    @State private var contentFocusGeneration = 0
    #endif
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
            .padding(.bottom, bottomContentPadding)
        }
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
        .onAppear {
            guard ReleaseScreenshotCaptureMode.isActive(),
                  let query = ReleaseScreenshotCaptureMode.searchQuery(),
                  viewModel.query != query else {
                return
            }
            viewModel.query = query
            viewModel.submitSearch()
        }
        #if os(tvOS)
        .onChange(of: contentFocusRequest) { _, _ in
            restoreContentFocus()
        }
        .onChange(of: viewModel.items.map(\.id)) { oldIDs, ids in
            guard focusedResultID != nil else { return }
            focusedResultID = PlinxTVFocusCoordinator.resolvedContentID(
                currentID: focusedResultID,
                previousIDs: oldIDs,
                availableIDs: ids
            )
        }
        .onChange(of: focusedResultID) { _, id in
            guard let id else { return }
            tvFocusCoordinator.rememberContentTarget(id, in: .search)
        }
        #endif
    }

    private var bottomContentPadding: CGFloat {
        #if os(tvOS)
        36
        #else
        120
        #endif
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(searchAccentColor)

            #if os(tvOS)
            PlinxTVTextEntry(
                text: $viewModel.query,
                placeholder: String(localized: "search.placeholder", table: "Plinx"),
                submitKind: .search,
                onTextChange: viewModel.queryDidChange,
                onSubmit: viewModel.submitSearch
            )
                .focused($searchFocused)
            #else
            TextField(text: $viewModel.query) {
                Text("search.placeholder", tableName: "Plinx")
                    .foregroundStyle(.white.opacity(0.52))
            }
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.white)
            .tint(searchAccentColor)
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit { viewModel.submitSearch() }
            .onChange(of: viewModel.query) { _, _ in viewModel.queryDidChange() }
            #endif

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
                .fill(PlinxBrand.surface.opacity(0.98))
        )
        #if os(tvOS)
        .plinxFocusSurface(isSelected: false, isFocused: searchFocused)
        .onMoveCommand { direction in
            guard direction == .up else { return }
            contentFocusGeneration &+= 1
            onRequestShellNavigationFocus()
        }
        #endif
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        if viewModel.query.isEmpty {
            emptyPrompt
        } else if viewModel.shouldShowTypingPrompt {
            liveSearchPrompt
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            PlinxLoadingStateView(
                role: .content,
                accessibilityLabel: LocalizedStringResource(
                    "search.loading",
                    table: "Plinx"
                ),
                accessibilityIdentifier: "search.loading"
            )
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
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
                #if os(tvOS)
                SearchResultButton(
                    item: item,
                    plexApiContext: plexApiContext,
                    isFocused: focusedResultID == item.id,
                    onSelect: { onSelectMedia(item) },
                    onLongPress: { onLongPressMedia(item) }
                )
                .focused($focusedResultID, equals: item.id)
                .onMoveCommand { direction in
                    guard direction == .up,
                          item.id == viewModel.items.first?.id else { return }
                    focusedResultID = nil
                    searchFocused = true
                }
                #else
                resultRow(item)
                    .plinxMediaCardInteraction(
                        onTap: { onSelectMedia(item) },
                        onLongPress: { onLongPressMedia(item) }
                    )
                #endif

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

    #if os(tvOS)
    private func restoreContentFocus() {
        let ids = viewModel.items.map(\.id)
        let remembered: String? = tvFocusCoordinator.rememberedContentTarget(
            in: .search,
            availableIDs: ids
        )
        let resultTarget = PlinxTVFocusCoordinator.resolvedContentID(
            currentID: focusedResultID,
            availableIDs: ids,
            preferredID: remembered
        )
        let focusesSearchField = resultTarget == nil || viewModel.query.isEmpty

        contentFocusGeneration &+= 1
        let generation = contentFocusGeneration
        searchFocused = false
        focusedResultID = nil

        Task { @MainActor in
            await Task.yield()
            guard generation == contentFocusGeneration else { return }
            if focusesSearchField {
                searchFocused = true
            } else {
                focusedResultID = resultTarget
            }
        }
    }
    #endif
}

#if os(tvOS)
private struct SearchResultButton: View {
    let item: MediaDisplayItem
    let plexApiContext: PlexAPIContext
    let isFocused: Bool
    let onSelect: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 18) {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: .thumb,
                        media: item
                    )
                )
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.primaryLabel)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let sub = item.secondaryLabel {
                        Text(sub)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }

                    if let rating = item.playableItem?.contentRating {
                        Text(rating)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.8)))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(isFocused ? 0.8 : 0.32))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.12) : Color.clear)
            )
            .plinxFocusSurface(isSelected: false, isFocused: isFocused)
        }
        .buttonStyle(PlinkButtonStyle())
        .focusEffectDisabled()
        .plinxQuickActionLongPress(onLongPress)
    }
}
#endif
