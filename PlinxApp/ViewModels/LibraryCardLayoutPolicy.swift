import Foundation
import UIKit

enum LibraryCardLayoutPolicy {
    enum DetailSurface: CaseIterable {
        case recommended
        case browse
        case collections
    }

    static let bannerArtworkCountStorageKey = "plinx.libraryBannerArtworkCount"
    static let hotReloadLibraryArtworkStorageKey = "plinx.libraryBannerHotReload"

    /// Portrait (poster) for standard movie/TV libraries; landscape (letterbox)
    /// for clip and none-agent libraries (YouTube, Home Videos).
    static func prefersLandscape(for library: Library) -> Bool {
        if library.isNoneAgentLibrary { return true }
        switch library.type {
        case .movie, .show:
            return false
        default:
            return true
        }
    }

    static func usesLandscapeDetailCards(for library: Library, surface: DetailSurface) -> Bool {
        // All library detail surfaces must agree. A prior regression fixed Browse
        // but left Collections as portrait posters for Other Videos.
        prefersLandscape(for: library)
    }

    static func maximumBannerArtworkDisplayCount(userInterfaceIdiom: UIUserInterfaceIdiom) -> Int {
        userInterfaceIdiom == .phone ? 3 : 5
    }

    static func defaultBannerArtworkDisplayCount(userInterfaceIdiom: UIUserInterfaceIdiom) -> Int {
        maximumBannerArtworkDisplayCount(userInterfaceIdiom: userInterfaceIdiom)
    }

    static func resolvedBannerArtworkDisplayCount(
        storedCount: Int,
        userInterfaceIdiom: UIUserInterfaceIdiom,
    ) -> Int {
        let fallback = defaultBannerArtworkDisplayCount(userInterfaceIdiom: userInterfaceIdiom)
        let requestedCount = storedCount > 0 ? storedCount : fallback
        return max(1, min(requestedCount, maximumBannerArtworkDisplayCount(userInterfaceIdiom: userInterfaceIdiom)))
    }
}
