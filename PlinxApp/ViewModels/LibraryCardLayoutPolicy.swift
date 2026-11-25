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

    /// Portrait (poster) for standard movie/TV libraries and Plex's "Shared with
    /// you" view; landscape (letterbox) for clip and none-agent libraries
    /// (YouTube, Home Videos) and everything else.
    static func prefersLandscape(for library: Library) -> Bool {
        if library.isNoneAgentLibrary { return true }
        if library.isShared { return false }
        switch library.type {
        case .movie, .series:
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

    /// Column count and card width for a library poster grid.
    struct GridMetrics: Equatable {
        let columnCount: Int
        let cardWidth: CGFloat
        let spacing: CGFloat

        /// The width the columns and gutters occupy. When the card width hits
        /// its cap this is narrower than the container, so the grid is centered.
        var contentWidth: CGFloat {
            CGFloat(columnCount) * cardWidth + CGFloat(max(columnCount - 1, 0)) * spacing
        }
    }

    /// Fits as many columns as `minimumCardWidth` allows, then widens the cards
    /// so the columns span the full width with equal gutters. Portrait posters
    /// and 16:9 thumbnails use separate minimums, so an iPhone in portrait shows
    /// three poster columns or two thumbnail columns instead of a narrow,
    /// left-aligned block.
    static func gridMetrics(availableWidth: CGFloat, usesLandscapeCards: Bool) -> GridMetrics {
        let spacing: CGFloat = 12
        let minimumWidth: CGFloat = usesLandscapeCards ? 160 : 104
        let maximumWidth: CGFloat = usesLandscapeCards ? 300 : 180
        let width = availableWidth.isFinite ? max(availableWidth, 0) : 0
        let columns = max(1, Int(((width + spacing) / (minimumWidth + spacing)).rounded(.down)))
        let fittedWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let cardWidth = max(min(fittedWidth, maximumWidth), 1).rounded(.down)
        return GridMetrics(columnCount: columns, cardWidth: cardWidth, spacing: spacing)
    }

    /// The tile also never shows more backdrops than the library preview
    /// returns (`LibraryPreview.artworkCount`).
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
