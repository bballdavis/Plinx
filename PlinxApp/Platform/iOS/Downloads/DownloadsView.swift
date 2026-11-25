import SwiftUI

@MainActor
struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @State private var selectedDownload: DownloadItem?
    @State private var downloadUsingCellular: DownloadItem?

    var body: some View {
        List {
            storageSection

            if !offlineCoordinator.availability.hasNetworkPath {
                Section {
                    DownloadsOfflineBanner()
                }
            }

            downloadsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("downloads.title")
        .fullScreenCover(item: $selectedDownload) { item in
            if isPlayable(item), let localURL = downloadManager.localVideoURL(for: item) {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        localMedia: downloadManager.playbackMedia(for: item),
                        localPlaybackURL: localURL,
                        localExternalSubtitles: downloadManager.localExternalSubtitles(for: item),
                        owner: downloadManager.owner(of: item),
                    ),
                )
            }
        }
        .confirmationDialog(
            "downloads.cellular.confirmation.title",
            isPresented: Binding(
                get: { downloadUsingCellular != nil },
                set: {
                    if !$0 {
                        downloadUsingCellular = nil
                    }
                },
            ),
            titleVisibility: .visible,
        ) {
            Button("downloads.cellular.confirmation.confirm") {
                guard let item = downloadUsingCellular else { return }
                downloadUsingCellular = nil
                Task {
                    await downloadManager.useCellularData(for: item)
                }
            }
            Button("common.actions.cancel", role: .cancel) {
                downloadUsingCellular = nil
            }
        } message: {
            Text("downloads.cellular.confirmation.message")
        }
    }

    private var storageSection: some View {
        Section {
            DownloadsStorageSummaryView(summary: downloadManager.storageSummary)
        }
    }

    /// Only the active profile's downloads that the current safety policy allows (fail closed): signed out, or with
    /// no active profile, nothing is offered.
    private var primaryItems: [DownloadItem] {
        downloadManager.sortedOwnedItems.filter(isAllowedBySafetyPolicy)
    }

    /// Other profiles' downloads, blocked ones and unowned legacy ones are listed only while the parent gate is
    /// unlocked, so a parent can delete them. They are never playable from here.
    private var otherItems: [DownloadItem] {
        guard ContentSafetyGate.shared.isParentUnlocked else { return [] }
        let primaryIDs = Set(primaryItems.map(\.id))
        return downloadManager.sortedItems.filter { !primaryIDs.contains($0.id) }
    }

    private func isAllowedBySafetyPolicy(_ item: DownloadItem) -> Bool {
        ContentSafetyGate.shared.isAllowed(downloadManager.playbackMedia(for: item))
    }

    private func isPlayable(_ item: DownloadItem) -> Bool {
        item.isPlayable && downloadManager.isOwnedByActiveUser(item) && isAllowedBySafetyPolicy(item)
    }

    @ViewBuilder
    private var downloadsSection: some View {
        if primaryItems.isEmpty, otherItems.isEmpty {
            ContentUnavailableView(
                "downloads.empty.title",
                systemImage: "arrow.down.circle",
                description: Text("downloads.empty.message"),
            )
            .listRowBackground(Color.clear)
        } else {
            if !primaryItems.isEmpty {
                Section("downloads.list.title") {
                    ForEach(primaryItems, content: interactiveRow)
                }
            }
            if !otherItems.isEmpty {
                Section {
                    ForEach(otherItems, content: interactiveRow)
                } header: {
                    Text("offline.downloads.others")
                } footer: {
                    Text("offline.downloads.others.footer")
                }
            }
        }
    }

    private func interactiveRow(_ item: DownloadItem) -> some View {
        downloadRow(item)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isPlayable(item) else { return }
                selectedDownload = item
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task {
                        await downloadManager.delete(item)
                    }
                } label: {
                    Label("common.actions.delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                if downloadManager.canRetry(item) {
                    Button {
                        downloadManager.retry(item)
                    } label: {
                        Label("common.actions.retry", systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        DownloadRow(
            item: item,
            title: downloadManager.localMediaItem(for: item)
                .spoilerSafeTitle(at: settingsManager.interface.spoilerProtection),
            posterURL: downloadManager.localPosterURL(for: item),
            isSpoilerProtected: isSpoilerProtected(item),
            isWaitingForWiFi: isWaitingForWiFi(item),
            onUseCellular: { downloadUsingCellular = item },
            onRetry: downloadManager.canRetry(item) ? { downloadManager.retry(item) } : nil,
        )
    }

    private func isWaitingForWiFi(_ item: DownloadItem) -> Bool {
        (item.allowsCellularAccess.map { !$0 } ?? settingsManager.downloads.wifiOnly)
            && downloadManager.isOnWiFi == false
            && item.progress == 0
            && item.taskIdentifier != nil
    }

    private func isSpoilerProtected(_ item: DownloadItem) -> Bool {
        downloadManager.localMediaItem(for: item)
            .isSpoilerProtected(at: settingsManager.interface.spoilerProtection)
    }
}
