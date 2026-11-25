import SwiftUI

/// Renders the absorbed rating model with Plinx-owned artwork.
///
/// The rating logos live in the Plinx asset catalog under `rating.*` names, so
/// no upstream branding assets are bundled.
struct MediaRatingLabel: View {
    let rating: MediaRating
    var iconHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            icon

            Text(verbatim: rating.formattedValue)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rating.accessibilityLabel))
    }

    @ViewBuilder
    private var icon: some View {
        switch rating.source {
        case .imdb:
            asset("rating.imdb")
        case .rottenTomatoesCritic, .jellyfinCritics:
            asset("rating.rt")
        case .rottenTomatoesAudience:
            asset("rating.rt.audience")
        case .tmdb:
            asset("rating.tmdb")
        case .jellyfinCommunity:
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: iconHeight))
        }
    }

    private func asset(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: iconHeight)
    }
}
