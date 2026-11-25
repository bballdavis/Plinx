import SwiftUI

/// Colored capsule naming the kind of a search result.
struct MediaTypeBadge: View {
    let type: MediaKind

    var body: some View {
        Text(label)
            .font(.badge)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15)),
            )
            .foregroundStyle(color)
    }

    private var label: String {
        switch type {
        case .movie:
            String(localized: "search.badge.movie")
        case .series:
            String(localized: "search.badge.show")
        case .season:
            String(localized: "search.badge.season")
        case .episode:
            String(localized: "search.badge.episode")
        case .clip:
            String(localized: "search.badge.clip")
        case .collection:
            String(localized: "search.badge.collection")
        case .playlist:
            String(localized: "search.badge.playlist")
        case .folder, .unknown:
            String(localized: "search.badge.unknown")
        }
    }

    private var color: Color {
        switch type {
        case .movie:
            .gray
        case .series:
            .mint
        case .season:
            .orange
        case .episode:
            .purple
        case .clip:
            .gray
        case .collection:
            .teal
        case .playlist:
            .indigo
        case .folder, .unknown:
            .gray
        }
    }
}
