import Foundation

enum QuickActionDownloadActionPolicy {
    enum Action {
        case download
        case goToDownloads
    }

    static func action(for media: MediaItem, downloadItems: [DownloadItem]) -> Action {
        hasPersistedDownload(for: media, downloadItems: downloadItems) ? .goToDownloads : .download
    }

    static func hasPersistedDownload(for media: MediaItem, downloadItems: [DownloadItem]) -> Bool {
        let eligibleItems = downloadItems.filter { $0.status != .failed }

        switch media.type {
        case .show:
            return eligibleItems.contains { item in
                item.ratingKey == media.id || item.metadata.grandparentRatingKey == media.id
            }
        case .season:
            return eligibleItems.contains { item in
                item.ratingKey == media.id || item.metadata.parentRatingKey == media.id
            }
        default:
            return eligibleItems.contains { $0.ratingKey == media.id }
        }
    }
}