import SwiftUI

/// Renders Strimr's rating model with Plinx-owned artwork.
///
/// Keeping this adapter in the app target avoids importing Strimr's full asset
/// catalogs, which would leak upstream branding into the Plinx bundle.
struct MediaRatingLabel: View {
    let rating: MediaRating
    var iconHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(height: iconHeight)

            Text(verbatim: rating.formattedValue)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rating.accessibilityLabel))
    }

    private var assetName: String {
        switch rating.source {
        case .imdb:
            "rating.imdb"
        case .rottenTomatoesCritic:
            "rating.rt"
        case .rottenTomatoesAudience:
            "rating.rt.audience"
        case .tmdb:
            "rating.tmdb"
        }
    }
}
