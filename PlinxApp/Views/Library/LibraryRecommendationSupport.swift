import OSLog
import PlinxCore
import PlinxUI
import SwiftUI

enum LibraryRecommendationFallbackPolicy {
    static let discoveryHubID = "plinx.discovery.recentlyAdded"

    static func needsDiscoveryHub(_ hubs: [Hub]) -> Bool {
        !hubs.contains { $0.hasItems && !isContinuationHub($0) }
    }

    static func discoveryItems(
        from candidates: [MediaDisplayItem],
        excluding hubs: [Hub],
        limit: Int = 24
    ) -> [MediaDisplayItem] {
        let existingIDs = Set(hubs.flatMap { $0.items.map(\.id) })
        var seen = existingIDs
        var items: [MediaDisplayItem] = []

        for candidate in candidates where seen.insert(candidate.id).inserted {
            items.append(candidate)
            if items.count == limit { break }
        }
        return items
    }

    private static func isContinuationHub(_ hub: Hub) -> Bool {
        let normalized = (hub.id + hub.title)
            .lowercased()
            .filter(\.isLetter)
        return normalized.contains("inprogress") || normalized.contains("continuewatching")
    }
}

@MainActor
enum PlinxLibraryRecommendationLoader {
    static func load(
        viewModel: LibraryRecommendedViewModel,
        context: PlexAPIContext,
        settingsManager: SettingsManager,
        policy: SafetyPolicy,
        refreshIfNeeded: Bool = false
    ) async {
        if refreshIfNeeded {
            await viewModel.refreshIfNeeded()
        } else {
            await viewModel.load()
        }

        var hubs = viewModel.hubs
        if LibraryRecommendationFallbackPolicy.needsDiscoveryHub(hubs) {
            if let catalog = try? await LibraryCatalogLoader(context: context).recentItems(
                for: viewModel.library,
                limit: 120,
                policy: policy
            ) {
                let items = LibraryRecommendationFallbackPolicy.discoveryItems(
                    from: catalog.items,
                    excluding: hubs
                )
                if !items.isEmpty {
                    hubs.append(
                        Hub(
                            id: LibraryRecommendationFallbackPolicy.discoveryHubID,
                            title: String(localized: "home.recentlyAdded.prefix", table: "Plinx"),
                            items: items
                        )
                    )
                }
            }
        }

        viewModel.hubs = visibleOrderedHubs(
            hubs,
            libraryID: viewModel.library.id,
            settingsManager: settingsManager
        )
    }

    private static func visibleOrderedHubs(
        _ hubs: [Hub],
        libraryID: String,
        settingsManager: SettingsManager
    ) -> [Hub] {
        let configuration = settingsManager.plinxLibraryViewSettings(for: libraryID)
        let hiddenIDs = Set(configuration.hiddenRecommendSectionIds)
        var seenIDs = Set<String>()
        let visible = hubs.filter {
            !hiddenIDs.contains($0.id) && seenIDs.insert($0.id).inserted
        }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let ordered = configuration.recommendSectionOrder.compactMap { byID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        return ordered + visible.filter { !orderedIDs.contains($0.id) }
    }
}

struct PlinxLibraryHubSection<Content: View>: View {
    let title: String
    let onViewAll: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        onViewAll: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onViewAll = onViewAll
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                titleView
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 40, height: 4)
            }
            .padding(.horizontal, 2)

            content
        }
    }

    @ViewBuilder
    private var titleView: some View {
        #if os(tvOS)
        titleText
        #else
        if let onViewAll {
            Button(action: onViewAll) {
                HStack(spacing: 5) {
                    titleText
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("hub.viewAll"))
        } else {
            titleText
        }
        #endif
    }

    private var titleText: some View {
        Text(title)
            #if os(tvOS)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            #else
            .font(.headline.weight(.semibold))
            #endif
            .foregroundStyle(.brandSecondary)
    }
}
