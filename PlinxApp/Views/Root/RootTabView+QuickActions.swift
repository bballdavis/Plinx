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
        guard PlinxContentAuthorization.isAllowed(item, policy: safetyPolicy) else {
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
            switch QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloadManager.items) {
            case .download:
                let downloadTitle: String
                switch media.type {
                case .show:
                    downloadTitle = "Download All Episodes"
                case .season:
                    downloadTitle = "Download Season"
                default:
                    downloadTitle = "Download Video"
                }

                actions.append(
                    PlinxQuickActionOption(
                        id: "download-\(media.id)",
                        title: downloadTitle,
                        systemImage: "arrow.down.circle",
                        role: nil,
                        action: {
                            guard PlinxContentAuthorization.isAllowed(media, policy: safetyPolicy) else {
                                quickActionErrorMessage = NSLocalizedString(
                                    "downloads.blockedByContentControls",
                                    tableName: "Plinx",
                                    comment: ""
                                )
                                return
                            }
                            Task {
                                guard sessionManager.plinxDownloadOwnerIdentity != nil else {
                                    quickActionErrorMessage = NSLocalizedString(
                                        "downloads.ownerUnavailable",
                                        tableName: "Plinx",
                                        comment: ""
                                    )
                                    return
                                }
                                switch media.type {
                                case .show:
                                    _ = await downloadManager.enqueueShow(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                case .season:
                                    _ = await downloadManager.enqueueSeason(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                default:
                                    _ = await downloadManager.enqueueItem(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                }
                            }
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

    func toggleWatched(_ item: MediaItem) async {
        guard !ReleaseScreenshotCaptureMode.isActive() else {
            selectedQuickActionMedia = nil
            return
        }

        do {
            let didMutate = try await watchStatusStore.toggle(
                item,
                context: plexApiContext,
                isAllowed: PlinxContentAuthorization.isAllowed(item, policy: safetyPolicy)
            )
            if didMutate {
                // Preserve the successful shared override while independently
                // owned source models reload from the server.
                await homeViewModel?.reload()
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
