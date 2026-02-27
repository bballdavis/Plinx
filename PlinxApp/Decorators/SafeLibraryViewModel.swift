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
    private(set) var bannerArtworkURLs: [String: [URL]] = [:]

    private let inner: LibraryViewModel
    private var policy: SafetyPolicy
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

    /// Updates the safety policy used for library artwork selection.
    /// The primary kid-safety filtering (content items) is enforced by
    /// `LibraryDetailView`, which reads the policy fresh from the environment
    /// on every render. This keeps the two in sync.
    func updatePolicy(_ newPolicy: SafetyPolicy) {
        policy = newPolicy
    }

    func artworkURL(for library: Library) -> URL? {
        inner.artworkURL(for: library)
    }

    func bannerArtworkURLs(for library: Library) -> [URL] {
        if let urls = bannerArtworkURLs[library.id], !urls.isEmpty {
            return urls
        }
        if let fallback = inner.artworkURL(for: library) {
            return [fallback]
        }
        return []
    }

    func ensureArtwork(for library: Library) async {
        guard bannerArtworkURLs[library.id]?.isEmpty ?? true else { return }
        await fetchBannerArtwork(for: library, forceRefresh: false)
    }

    func refreshArtwork(for library: Library) async {
        await fetchBannerArtwork(for: library, forceRefresh: true)
    }

    private func fetchBannerArtwork(for library: Library, forceRefresh: Bool) async {
        if !forceRefresh, let existing = bannerArtworkURLs[library.id], !existing.isEmpty {
            return
        }

        guard let sectionId = library.sectionId else { return }

        do {
            let sectionRepository = try SectionRepository(context: context)
            let imageRepository = try ImageRepository(context: context)

            let itemContainer = try await sectionRepository.getSectionsItems(
                sectionId: sectionId,
                params: SectionRepository.SectionItemsParams(sort: "random", limit: 60),
                pagination: PlexPagination(start: 0, size: 60)
            )

            let safeItems = (itemContainer.mediaContainer.metadata ?? []).compactMap { item -> PlexItem? in
                let displayItem = MediaDisplayItem.playable(MediaItem(plexItem: item))
                guard StrimrAdapter.isAllowed(displayItem, policy: policy) else { return nil }
                guard item.art != nil || item.thumb != nil else { return nil }
                return item
            }

            var uniqueRatingKeys: Set<String> = []
            var uniqueURLs: Set<String> = []
            var urls: [URL] = []

            for item in safeItems {
                guard uniqueRatingKeys.insert(item.ratingKey).inserted else { continue }

                guard
                    let path = item.art ?? item.thumb,
                    let url = imageRepository.transcodeImageURL(path: path, width: 800, height: 450),
                    uniqueURLs.insert(url.absoluteString).inserted
                else {
                    continue
                }

                urls.append(url)
                if urls.count == 5 { break }
            }

            if !urls.isEmpty {
                let randomizedURLs = urls.shuffled()
                bannerArtworkURLs[library.id] = randomizedURLs
                inner.artworkURLs[library.id] = randomizedURLs[0]
                return
            }
        } catch {
            ErrorReporter.capture(error)
        }

        // Fallback to vendor single-artwork loader if no validated image found.
        await inner.ensureArtwork(for: library)
        if let fallback = inner.artworkURL(for: library) {
            bannerArtworkURLs[library.id] = [fallback]
        }
    }
}
