import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#endif

struct OfflineRootView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.safetyPolicy) private var safetyPolicy

    @State private var selectedTab: MainCoordinator.Tab = .home
    @State private var selectedDownload: DownloadItem?

    private var visibleTabs: [KidsMainTabPicker.TabItem] {
        KidsMainTabPicker.TabItem.mainTabs(includeDownloads: true, showSearchInMainNavigation: false)
            .filter { tab in
                switch tab.tab {
                case .home, .library, .more:
                    return true
                default:
                    return false
                }
            }
    }

    private var snapshot: OfflineContentSnapshot {
        OfflineContentBuilder.buildSnapshot(
            downloadItems: downloadManager.sortedItems,
            libraries: libraryStore.libraries,
            policy: safetyPolicy
        )
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch selectedTab {
            case .library:
                NavigationStack {
                    OfflineLibraryView(snapshot: snapshot) { item in
                        selectedDownload = item
                    }
                }
            case .more:
                NavigationStack {
                    PlinxDownloadsGridView()
                }
            default:
                NavigationStack {
                    OfflineHomeView(snapshot: snapshot) { item in
                        selectedDownload = item
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KidsMainTabPicker(
                tabs: visibleTabs,
                selectedTab: Binding(
                    get: { selectedTab },
                    set: { selectedTab = $0 }
                )
            )
        }
        .fullScreenCover(item: $selectedDownload) { item in
            OfflineDownloadPlayerView(item: item)
        }
    }
}

private struct OfflineHomeView: View {
    let snapshot: OfflineContentSnapshot
    let onSelectDownload: (DownloadItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                headerRow

                if snapshot.homeSections.isEmpty {
                    offlineEmptyState(
                        title: "No downloaded videos available",
                        message: "Connect to the internet to download videos, or open Downloads to manage existing items."
                    )
                } else {
                    ForEach(snapshot.homeSections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Offline Mode")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Showing downloaded videos only.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func sectionView(_ section: OfflineHomeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.items) { item in
                        OfflineMediaCard(item: item, layout: section.layout) {
                            onSelectDownload(item)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct OfflineLibraryView: View {
    let snapshot: OfflineContentSnapshot
    let onSelectDownload: (DownloadItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Library")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Downloaded libraries available offline.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if snapshot.libraries.isEmpty {
                    offlineEmptyState(
                        title: "No offline libraries",
                        message: "Downloaded movies and episodes will appear here once they finish downloading."
                    )
                } else {
                    ForEach(snapshot.libraries) { group in
                        NavigationLink {
                            OfflineLibraryDetailView(group: group, onSelectDownload: onSelectDownload)
                        } label: {
                            OfflineLibraryTile(group: group)
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 120)
        }
    }
}

private struct OfflineLibraryDetailView: View {
    let group: OfflineLibraryGroup
    let onSelectDownload: (DownloadItem) -> Void

    private var layout: OfflineHomeSection.Layout {
        LibraryCardLayoutPolicy.prefersLandscape(for: group.library) ? .landscape : .portrait
    }

    private var gridColumns: [GridItem] {
        let cardWidth: CGFloat = layout == .landscape ? 200 : 112
        return [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(group.items) { item in
                    OfflineMediaCard(item: item, layout: layout) {
                        onSelectDownload(item)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .navigationTitle(group.library.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OfflineLibraryTile: View {
    let group: OfflineLibraryGroup

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OfflineLibraryBanner(group: group)

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: group.library.iconName)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(group.library.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct OfflineLibraryBanner: View {
    let group: OfflineLibraryGroup

    var body: some View {
        GeometryReader { proxy in
            let items = Array(group.items.prefix(3))

            if items.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            } else {
                HStack(spacing: 4) {
                    ForEach(items) { item in
                        OfflinePosterArtwork(item: item)
                            .frame(width: (proxy.size.width - CGFloat(max(items.count - 1, 0)) * 4) / CGFloat(items.count), height: proxy.size.height)
                            .clipped()
                    }
                }
            }
        }
    }
}

private struct OfflineMediaCard: View {
    let item: DownloadItem
    let layout: OfflineHomeSection.Layout
    let onTap: () -> Void

    private var cardWidth: CGFloat {
        layout == .landscape ? 200 : 112
    }

    private var cardHeight: CGFloat {
        layout == .landscape ? (cardWidth / (16.0 / 9.0)) : (cardWidth / (2.0 / 3.0))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    OfflinePosterArtwork(item: item)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let progress = progressFraction {
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.30))
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: cardWidth * CGFloat(progress))
                        }
                        .frame(height: 5)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Text(item.metadata.title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)

                if let subtitle = item.metadata.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .frame(width: cardWidth, alignment: .leading)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var progressFraction: Double? {
        guard let duration = item.metadata.duration, duration > 0,
              let viewOffset = item.metadata.viewOffset,
              viewOffset > 0 else { return nil }
        return min(1, viewOffset / duration)
    }
}

private struct OfflinePosterArtwork: View {
    @Environment(DownloadManager.self) private var downloadManager

    let item: DownloadItem

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let posterURL = downloadManager.localPosterURL(for: item),
               let image = PlatformImage(contentsOfFile: posterURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.08))
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
            Text("No artwork")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private func offlineEmptyState(title: String, message: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: "arrow.down.circle")
            .font(.title)
            .foregroundStyle(.white.opacity(0.7))
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.vertical, 32)
}