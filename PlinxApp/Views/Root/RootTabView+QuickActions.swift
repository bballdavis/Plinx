import PlinxCore
import PlinxUI
import SwiftUI

extension RootTabView {
    func quickActionSheet(for item: MediaDisplayItem) -> some View {
        PlinxQuickActionMenu(
            title: item.title,
            options: quickActionOptions(for: item),
            onDismiss: { selectedQuickActionMedia = nil }
        )
    }

    func presentQuickActions(for item: MediaDisplayItem, showsPrimary: Bool = true) {
        guard ContentSafetyGate.shared.isAllowed(item) else {
            quickActionErrorMessage = String(localized: "media.unavailable.title", table: "Plinx")
            return
        }
        quickActionShowsPrimary = showsPrimary
        selectedQuickActionMedia = item
    }

    func quickActionOptions(for item: MediaDisplayItem) -> [PlinxQuickActionOption] {
        switch item {
        case let .playable(media):
            var actions: [PlinxQuickActionOption] = []
            if quickActionShowsPrimary {
                actions.append(PlinxQuickActionOption(
                    id: "play",
                    title: String(localized: "common.actions.play"),
                    systemImage: "play.fill",
                    role: nil,
                    action: {
                        handlePrimarySelection(item)
                    }
                ))
            }
            actions.append(
                PlinxQuickActionOption(
                    id: "toggle-watched",
                    title: isWatched(media)
                        ? String(localized: "quickActions.markUnwatched", table: "Plinx")
                        : String(localized: "quickActions.markWatched", table: "Plinx"),
                    systemImage: isWatched(media) ? "checkmark.circle.fill" : "checkmark.circle",
                    role: nil,
                    action: {
                        Task { await toggleWatched(media) }
                    }
                )
            )

            #if !os(tvOS)
            // Only this profile's downloads count: another profile's copy of
            // the same title never turns Download into "Go to downloads".
            switch QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloadManager.ownedItems) {
            case .download:
                let downloadTitle = switch media.type {
                case .series:
                    "Download All Episodes"
                case .season:
                    "Download Season"
                default:
                    "Download Video"
                }

                actions.append(
                    PlinxQuickActionOption(
                        id: "download-\(media.id)",
                        title: downloadTitle,
                        systemImage: "arrow.down.circle",
                        role: nil,
                        action: {
                            enqueueDownload(of: media)
                        }
                    )
                )
            case .goToDownloads:
                actions.append(
                    PlinxQuickActionOption(
                        id: "go-downloads-\(media.id)",
                        title: "Go to downloads",
                        systemImage: "arrow.down.circle.fill",
                        role: nil,
                        action: {
                            mainCoordinator.resetToRoot(for: .more)
                            mainCoordinator.tab = .more
                        }
                    )
                )
            }
            #endif

            if quickActionShowsPrimary {
                actions.append(PlinxQuickActionOption(
                    id: "go-details",
                    title: String(localized: "quickActions.moreInfo", table: "Plinx"),
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showMediaDetail(media)
                    }
                ))
            }

            return actions

        case let .collection(collection):
            return [
                PlinxQuickActionOption(
                    id: "collection-details-\(collection.id)",
                    title: String(localized: "quickActions.moreInfo", table: "Plinx"),
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showCollectionDetail(collection)
                    }
                ),
            ]

        case let .playlist(playlist):
            return [
                PlinxQuickActionOption(
                    id: "playlist-play-\(playlist.id)",
                    title: String(localized: "common.actions.play"),
                    systemImage: "play.fill",
                    role: nil,
                    action: {
                        handlePrimarySelection(item)
                    }
                ),
                PlinxQuickActionOption(
                    id: "playlist-details-\(playlist.id)",
                    title: String(localized: "quickActions.moreInfo", table: "Plinx"),
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showPlaylistDetail(playlist)
                    }
                ),
            ]
        }
    }

    #if !os(tvOS)
    /// Downloads use the item's own server; the item is re-checked against
    /// the content policy here, and the download services of the safety
    /// boundary filter every episode of a series or season.
    func enqueueDownload(of media: MediaItem) {
        guard ContentSafetyGate.shared.isAllowed(media) else {
            quickActionErrorMessage = String(localized: "downloads.blockedByContentControls", table: "Plinx")
            return
        }
        guard let services = registry.services(for: media.identity.server) else {
            quickActionErrorMessage = String(localized: "downloads.ownerUnavailable", table: "Plinx")
            return
        }
        Task {
            switch media.type {
            case .series, .season:
                await downloadManager.enqueueItems(itemID: media.id, kind: media.type, services: services)
            default:
                await downloadManager.enqueueItem(itemID: media.id, services: services)
            }
        }
    }
    #endif

    func toggleWatched(_ item: MediaItem) async {
        guard !ReleaseScreenshotCaptureMode.isActive() else {
            selectedQuickActionMedia = nil
            return
        }
        guard let services = registry.services(for: item.identity.server) else {
            quickActionErrorMessage = String(localized: "server.unavailable.title")
            return
        }

        do {
            let didMutate = try await watchStatusStore.toggle(
                item,
                services: services,
                isAllowed: ContentSafetyGate.shared.isAllowed(item)
            )
            if didMutate {
                // Preserve the successful shared override while the home
                // reloads this server from the server's own state.
                await homeViewModel.refresh(server: services.identity)
            }
        } catch {
            quickActionErrorMessage = error.localizedDescription
        }
    }

    func isWatched(_ item: MediaItem) -> Bool {
        watchStatusStore.isWatched(item)
    }

    func isWatchedDisplay(_ item: MediaDisplayItem) -> Bool {
        watchStatusStore.isWatched(item)
    }
}
