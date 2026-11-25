#if !os(tvOS)
import Foundation

/// Whether a title's quick-action menu offers "Download" or "Go to downloads".
///
/// Callers pass the active profile's downloads (`DownloadManager.ownedItems`),
/// so another profile's copy never hides the Download action. Only downloads
/// from the title's own server count, and failed downloads do not count: the
/// title can be downloaded again.
enum QuickActionDownloadActionPolicy {
    enum Action {
        case download
        case goToDownloads
    }

    static func action(for media: MediaItem, downloadItems: [DownloadItem]) -> Action {
        hasPersistedDownload(for: media, downloadItems: downloadItems) ? .goToDownloads : .download
    }

    static func hasPersistedDownload(for media: MediaItem, downloadItems: [DownloadItem]) -> Bool {
        let server = media.identity.server
        let eligibleItems = downloadItems.filter { item in
            item.status != .failed && item.identity?.server == server
        }

        switch media.type {
        case .series:
            return eligibleItems.contains { item in
                item.itemID == media.id || item.metadata.grandparentRatingKey == media.id
            }
        case .season:
            return eligibleItems.contains { item in
                item.itemID == media.id || item.metadata.parentRatingKey == media.id
            }
        default:
            return eligibleItems.contains { $0.itemID == media.id }
        }
    }
}
#endif
