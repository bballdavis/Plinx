import Foundation

/// The loaded run of a library browse listing, from its first position up to
/// the first position whose page has not arrived yet.
///
/// The shared browse view models page by position. Plinx shows the run as
/// one continuous grid and asks for `nextIndex` when the grid reaches its end,
/// so items it leaves out (collections of movie and TV libraries, which have
/// their own tab) never leave holes.
@MainActor
struct PlinxLibraryBrowseListing {
    let items: [LibraryBrowseItem]
    /// First position still to load; `nil` once the whole listing is loaded.
    let nextIndex: Int?

    init(
        itemsByIndex: [Int: LibraryBrowseItem],
        totalItemCount: Int,
        library: Library,
        gate: ContentSafetyGate = .shared,
    ) {
        var items: [LibraryBrowseItem] = []
        var index = 0
        while index < totalItemCount, let item = itemsByIndex[index] {
            if Self.isShown(item, in: library, gate: gate) {
                items.append(item)
            }
            index += 1
        }
        self.items = items
        nextIndex = index < totalItemCount ? index : nil
    }

    /// Every item passes the gate again here: the "downloaded only" listing
    /// reads the device's offline store rather than the safe services.
    static func isShown(_ item: LibraryBrowseItem, in library: Library, gate: ContentSafetyGate) -> Bool {
        if case let .media(media) = item, case .collection = media,
           library.type == .movie || library.type == .series
        {
            return false
        }
        return gate.isAllowed(item)
    }
}
