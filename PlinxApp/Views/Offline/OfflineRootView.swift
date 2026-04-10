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
    @State private var libraryNavigationPath: [OfflineLibraryGroup] = []
    @State private var showSettings = false

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
                NavigationStack(path: $libraryNavigationPath) {
                    OfflineLibraryView(
                        snapshot: snapshot,
                        onOpenSettings: { showSettings = true },
                        onOpenLibrary: { group in
                            libraryNavigationPath.append(group)
                        },
                        onSelectDownload: { item in
                            selectedDownload = item
                        },
                        onRefresh: checkConnectivity
                    )
                    .navigationDestination(for: OfflineLibraryGroup.self) { group in
                        OfflineLibraryDetailView(
                            group: group,
                            onSelectDownload: { item in
                                selectedDownload = item
                            },
                            onRefresh: checkConnectivity
                        )
                    }
                }
            case .more:
                NavigationStack {
                    PlinxDownloadsGridView()
                }
            default:
                NavigationStack {
                    OfflineHomeView(
                        snapshot: snapshot,
                        onOpenSettings: { showSettings = true },
                        onSelectDownload: { item in
                            selectedDownload = item
                        },
                        onRefresh: checkConnectivity
                    )
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
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                PlinxSettingsView()
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        settingsHeaderRow
                    }
            }
            .presentationDetents([.large])
        }
    }

    /// Pull-to-refresh handler. Ask the network monitor whether we're back
    /// online; if the path is satisfied `isOffline` flips to false and
    /// `PlinxContentView`'s onChange drives session hydration automatically.
    private func checkConnectivity() async {
        guard downloadManager.isOffline else { return }
        await downloadManager.recheckNetworkStatus()
    }

    private var settingsHeaderRow: some View {
        HStack(spacing: 12) {
            Text("tabs.settings".plinxLocalized)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            PlinxChromeButton(systemImage: "xmark") {
                showSettings = false
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

private struct OfflineBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 10, weight: .bold))
            Text("Offline")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.85))
        )
    }
}

private struct OfflineHomeView: View {
    let snapshot: OfflineContentSnapshot
    let onOpenSettings: () -> Void
    let onSelectDownload: (DownloadItem) -> Void
    let onRefresh: () async -> Void

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
        .accessibilityIdentifier("offline.home.scroll")
        .refreshable { await onRefresh() }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image("LogoColor")
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .accessibilityHidden(true)

            Text("Home")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))

            OfflineBadge()

            if OfflineReconnectUITestFixtures.isActive() {
                Button("Reconnect") {
                    Task { await onRefresh() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("offlineReconnect.trigger")
            }

            Spacer()

            PlinxChromeButton(systemImage: "gearshape.fill") {
                onOpenSettings()
            }
            .accessibilityIdentifier("offline.home.header.settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
    let onOpenSettings: () -> Void
    let onOpenLibrary: (OfflineLibraryGroup) -> Void
    let onSelectDownload: (DownloadItem) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Library")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.95))

                    OfflineBadge()

                    Spacer()

                    PlinxChromeButton(systemImage: "gearshape.fill") {
                        onOpenSettings()
                    }
                    .accessibilityIdentifier("offline.library.header.settings")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)

                if snapshot.libraries.isEmpty {
                    offlineEmptyState(
                        title: "No offline libraries",
                        message: "Downloaded movies and episodes will appear here once they finish downloading."
                    )
                } else {
                    ForEach(snapshot.libraries) { group in
                        Button {
                            onOpenLibrary(group)
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
        .refreshable { await onRefresh() }
    }
}

private struct OfflineLibraryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let group: OfflineLibraryGroup
    let onSelectDownload: (DownloadItem) -> Void
    let onRefresh: () async -> Void

    private var layout: OfflineHomeSection.Layout {
        LibraryCardLayoutPolicy.prefersLandscape(for: group.library) ? .landscape : .portrait
    }

    private var gridColumns: [GridItem] {
        let cardWidth: CGFloat = layout == .landscape ? 200 : 112
        return [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                detailHeader

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
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await onRefresh() }
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            PlinxChromeButton(systemImage: "chevron.left") {
                dismiss()
            }

            Text(group.library.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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