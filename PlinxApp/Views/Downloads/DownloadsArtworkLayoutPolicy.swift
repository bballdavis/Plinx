import CoreGraphics

struct DownloadsArtworkLayoutPolicy {
    static let portraitAspectRatio: CGFloat = 2.0 / 3.0
    static let minimumLandscapeAspectRatio: CGFloat = 16.0 / 9.0
    static let minimumClampedLandscapeRatio: CGFloat = 1.2
    static let maximumLandscapeAspectRatio: CGFloat = 2.2

    static func isPortraitArtworkType(_ artworkLayoutStyle: DownloadArtworkLayoutStyle) -> Bool {
        artworkLayoutStyle.isPortrait
    }

    static func displayAspectRatio(for artworkLayoutStyle: DownloadArtworkLayoutStyle, imageSize: CGSize?) -> CGFloat {
        if isPortraitArtworkType(artworkLayoutStyle) {
            return portraitAspectRatio
        }

        let baseRatio: CGFloat
        if let imageSize {
            let width = max(imageSize.width, 1)
            let height = max(imageSize.height, 1)
            baseRatio = width / height
        } else {
            baseRatio = minimumLandscapeAspectRatio
        }

        let clamped = max(minimumClampedLandscapeRatio, min(maximumLandscapeAspectRatio, baseRatio))
        return max(minimumLandscapeAspectRatio, clamped)
    }
}