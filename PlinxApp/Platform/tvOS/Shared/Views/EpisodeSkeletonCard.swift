import SwiftUI

/// Same footprint as an episode card, so switching seasons does not change the page height.
struct EpisodeSkeletonCard: View {
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous)
                .fill(.surfaceSubtle)
                .frame(width: width, height: width * 9 / 16)
            VStack(alignment: .leading, spacing: 4) {
                SkeletonLine(font: .cardTitle, fraction: 0.7)
                SkeletonLine(font: .cardMetadata, fraction: 0.25)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
