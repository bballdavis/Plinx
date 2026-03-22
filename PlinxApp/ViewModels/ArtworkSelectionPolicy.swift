import Foundation

enum ArtworkSelectionPolicy {
    static func artworkKind(
        forHomeSection sectionKey: String,
        item: MediaDisplayItem,
        isLandscape: Bool,
    ) -> MediaImageViewModel.ArtworkKind {
        guard isLandscape else { return .thumb }
        // Use thumb for other videos, clips, and continue watching clips
        if sectionKey == "otherVideos"
            || sectionKey == "continueWatching.otherVideos"
            || item.type == .clip {
            return .thumb
        }
        return .art
    }

    static func preferredLandscapeArtworkKind(for library: Library) -> MediaImageViewModel.ArtworkKind? {
        guard LibraryCardLayoutPolicy.prefersLandscape(for: library) else { return nil }
        if library.isNoneAgentLibrary || library.type == .clip {
            return .thumb
        }
        return .art
    }
}