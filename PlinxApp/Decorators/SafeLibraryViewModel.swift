import Foundation
import Observation
import PlinxCore

/// Wraps Strimr's `LibraryViewModel` for Plinx.
///
/// The top-level library list (sections / channels) is safe metadata.
/// Item-level safety filtering happens inside library browse/detail views.
/// This decorator primarily passes through and provides API symmetry with
/// other Safe*ViewModels.
@MainActor
@Observable
final class SafeLibraryViewModel {
    var libraries: [Library] { inner.libraries }
    var isLoading: Bool { inner.isLoading }
    private(set) var errorMessage: String?

    private let inner: LibraryViewModel
    private let policy: SafetyPolicy
    private let context: PlexAPIContext

    init(inner: LibraryViewModel, policy: SafetyPolicy = .ratingOnly(), context: PlexAPIContext) {
        self.inner = inner
        self.policy = policy
        self.context = context
    }

    func load() async {
        await inner.load()
        errorMessage = inner.errorMessage
    }

    func artworkURL(for library: Library) -> URL? {
        inner.artworkURL(for: library)
    }

    func ensureArtwork(for library: Library) async {
        guard inner.artworkURLs[library.id] == nil else { return }
        guard let sectionId = library.sectionId else { return }
        
        do {
            let sectionRepository = try SectionRepository(context: context)
            let imageRepository = try ImageRepository(context: context)
            
            let itemContainer = try await sectionRepository.getSectionsItems(
                sectionId: sectionId,
                params: SectionRepository.SectionItemsParams(sort: "random", limit: 20),
                pagination: PlexPagination(start: 0, size: 20)
            )
            
            let safeItems = (itemContainer.mediaContainer.metadata ?? []).compactMap { item -> PlexItem? in
                let displayItem = MediaDisplayItem.playable(MediaItem(plexItem: item))
                return StrimrAdapter.isAllowed(displayItem, policy: policy) ? item : nil
            }
            
            if let item = safeItems.first {
                let path = item.art ?? item.thumb
                if let url = path.flatMap({ imageRepository.transcodeImageURL(path: $0, width: 800, height: 450) }) {
                    inner.artworkURLs[library.id] = url
                }
            }
        } catch {
            // Fallback to inner if needed, or just ignore
            await inner.ensureArtwork(for: library)
        }
    }
}
