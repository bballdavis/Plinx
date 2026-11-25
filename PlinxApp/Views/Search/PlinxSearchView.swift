import PlinxUI
import SwiftUI

/// Plinx search on the upstream multi-server `SearchViewModel`.
///
/// Every server's search service is wrapped by `SafeMediaServices`, so
/// results arrive filtered; the page re-checks them against the gate so
/// results from before a policy change never show. Copies of a title on
/// several servers appear once, and selecting it uses the best reachable
/// copy without asking a child to pick a server.
struct PlinxSearchView: View {
    /// Typing searches live only from this many characters; Search on the
    /// keyboard always searches.
    static let minimumLiveSearchCharacters = 4

    @State private var viewModel: SearchViewModel
    private let topContent: AnyView?
    private let onRequestShellNavigationFocus: () -> Void
    private let contentFocusRequest: Int
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let onLongPressMedia: (MediaDisplayItem) -> Void

    @Environment(ServerRegistry.self) private var registry
    @FocusState private var searchFocused: Bool
    /// True once the current query was searched, live or submitted.
    @State private var hasSearched = false
    #if os(tvOS)
    @EnvironmentObject private var tvFocusCoordinator: PlinxTVFocusCoordinator
    @FocusState private var focusedResultID: String?
    @State private var contentFocusGeneration = 0
    #endif

    init(
        viewModel: SearchViewModel,
        topContent: AnyView? = nil,
        onRequestShellNavigationFocus: @escaping () -> Void = {},
        contentFocusRequest: Int = 0,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void,
        onLongPressMedia: @escaping (MediaDisplayItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.topContent = topContent
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
        self.contentFocusRequest = contentFocusRequest
        self.onSelectMedia = onSelectMedia
        self.onLongPressMedia = onLongPressMedia
    }

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
        .onChange(of: ContentSafetyGate.shared.revision) { _, _ in
            // Results ranked under the previous policy are searched again.
            guard hasSearched else { return }
            viewModel.submitSearch()
        }
        .onAppear {
            guard ReleaseScreenshotCaptureMode.isActive(),
                  let query = ReleaseScreenshotCaptureMode.searchQuery(),
                  viewModel.query != query else {
                return
            }
            viewModel.query = query
            submitSearch()
        }
        #if os(tvOS)
        .onChange(of: contentFocusRequest) { _, _ in
            restoreContentFocus()
        }
        .onChange(of: visibleResults.map(\.id)) { oldIDs, ids in
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

    // MARK: - Query

    private var trimmedQuery: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowTypingPrompt: Bool {
        viewModel.hasQuery && !hasSearched && trimmedQuery.count < Self.minimumLiveSearchCharacters
    }

    private var remainingCharactersForLiveSearch: Int {
        max(Self.minimumLiveSearchCharacters - trimmedQuery.count, 0)
    }

    private func queryDidChange() {
        if !viewModel.hasQuery {
            hasSearched = false
            // Clears the results and cancels a pending search.
            viewModel.queryDidChange()
        } else if trimmedQuery.count >= Self.minimumLiveSearchCharacters {
            hasSearched = true
            viewModel.queryDidChange()
        } else {
            // Too short to search live; the typing prompt hides older results.
            hasSearched = false
        }
    }

    private func submitSearch() {
        hasSearched = viewModel.hasQuery
        viewModel.submitSearch()
    }

    private func clear() {
        viewModel.query = ""
        hasSearched = false
        viewModel.queryDidChange()
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
                onTextChange: queryDidChange,
                onSubmit: submitSearch
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
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit(submitSearch)
            .onChange(of: viewModel.query) { _, _ in queryDidChange() }
            #endif

            if !viewModel.query.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.system(size: 18))
                }
                .accessibilityLabel(Text(String(
                    localized: "search.clear",
                    defaultValue: "Clear search",
                    table: "Plinx"
                )))
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

    /// Merged results whose shown copy the current policy allows.
    private var visibleResults: [MergedSearchResult] {
        let gate = ContentSafetyGate.shared
        _ = gate.revision
        return viewModel.filteredItems.filter { gate.isAllowed($0.media) }
    }

    @ViewBuilder
    private var resultsContent: some View {
        let results = shouldShowTypingPrompt ? [] : visibleResults
        if !viewModel.hasQuery {
            emptyPrompt
        } else if shouldShowTypingPrompt {
            liveSearchPrompt
        } else if viewModel.isLoading && results.isEmpty {
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
        } else if results.isEmpty {
            Group {
                if let errorMessage = viewModel.errorMessage {
                    // Every server failed to answer.
                    Text(errorMessage)
                } else {
                    Text("search.no_results \(trimmedQuery)", tableName: "Plinx")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            resultsList(results)
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
            Text("search.live.minimum \(Int64(remainingCharactersForLiveSearch))", tableName: "Plinx")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func resultsList(_ results: [MergedSearchResult]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(results) { result in
                let item = preferredMedia(for: result)
                #if os(tvOS)
                SearchResultButton(
                    item: item,
                    services: registry.services(for: item.server),
                    isFocused: focusedResultID == result.id,
                    onSelect: { onSelectMedia(item) },
                    onLongPress: { onLongPressMedia(item) }
                )
                .focused($focusedResultID, equals: result.id)
                .onMoveCommand { direction in
                    guard direction == .up,
                          result.id == results.first?.id else { return }
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

    /// The copy a child gets: the best quality one on a server that is ready,
    /// else the one the result shows. A child is never asked to pick a server.
    private func preferredMedia(for result: MergedSearchResult) -> MediaDisplayItem {
        let gate = ContentSafetyGate.shared
        let readyServers = registry.readyServers
        let source = result.sourcesByQuality.first { source in
            readyServers.contains(source.server) && gate.isAllowed(source.media)
        } ?? result.primarySource
        return source.media
    }

    #if !os(tvOS)
    private func resultRow(_ item: MediaDisplayItem) -> some View {
        HStack(spacing: 14) {
            ItemArtworkView(
                services: registry.services(for: item.server),
                kind: .thumb,
                media: item
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
    #endif

    #if os(tvOS)
    private func restoreContentFocus() {
        let ids = visibleResults.map(\.id)
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
    let services: MediaServices?
    let isFocused: Bool
    let onSelect: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 18) {
                ItemArtworkView(services: services, kind: .thumb, media: item)
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
