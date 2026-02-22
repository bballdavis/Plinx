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

    init(inner: LibraryViewModel, policy: SafetyPolicy = .ratingOnly()) {
        self.inner = inner
        self.policy = policy
    }

    func load() async {
        await inner.load()
        errorMessage = inner.errorMessage
    }

    func artworkURL(for library: Library) -> URL? {
        inner.artworkURL(for: library)
    }

    func ensureArtwork(for library: Library) async {
        await inner.ensureArtwork(for: library)
    }
}
