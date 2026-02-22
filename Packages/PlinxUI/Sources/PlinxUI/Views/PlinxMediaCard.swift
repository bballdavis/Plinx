import SwiftUI

/// A reusable media thumbnail card used throughout Plinx.
///
/// Shows a poster image (via `AsyncImage`), optional progress bar, and labels.
/// Does not import any Strimr types — data must be pre-adapted by the caller.
public struct PlinxMediaCard: View {
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    /// Watch progress from `0.0` to `1.0`. `nil` hides the bar.
    public let progress: Double?
    public let aspectRatio: CGFloat

    @Environment(\.plinxTheme) private var theme

    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL? = nil,
        progress: Double? = nil,
        aspectRatio: CGFloat = 2 / 3
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.progress = progress
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                // Poster image
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Rectangle().fill(.gray.opacity(0.3))
                            .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.5)))
                    default:
                        Rectangle().fill(.gray.opacity(0.15))
                            .overlay(ProgressView())
                    }
                }
                .clipped()

                // Progress bar
                if let progress, progress > 0 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(theme.palette.accent)
                            .frame(width: geo.size.width * CGFloat(min(progress, 1.0)), height: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
