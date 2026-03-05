import Foundation

enum LibraryCardLayoutPolicy {

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
}
