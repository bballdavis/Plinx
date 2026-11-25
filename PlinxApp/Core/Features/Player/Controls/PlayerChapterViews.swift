import SwiftUI

extension MediaChapter {
    var displayTitle: String {
        title.isEmpty ? String(localized: "player.chapters.number \(index)") : title
    }

    var startTimeText: String {
        playerTimestampText(startTime)
    }

    func accessibilityDescription(totalCount: Int, isCurrent: Bool) -> String {
        if isCurrent {
            return String(
                localized: "player.chapters.accessibility.current \(index) \(totalCount) \(startTimeText)",
            )
        }
        return String(
            localized: "player.chapters.accessibility \(index) \(totalCount) \(startTimeText)",
        )
    }
}

struct PlayerChapterArtworkView: View {
    @Environment(MediaServices.self) private var services: MediaServices?

    var artworkPath: String?
    var width: Int
    var height: Int

    @State private var resource: ArtworkResource?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let resource {
                ArtworkResourceView(resource: resource)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: loadID) {
            await loadArtwork()
        }
    }

    private var loadID: String {
        "\(artworkPath ?? "")|\(width)x\(height)"
    }

    private func loadArtwork() async {
        resource = nil
        guard let artworkPath, let services else {
            isLoading = false
            return
        }

        isLoading = true
        do {
            let loadedResource = try await services.artwork.artwork(
                path: artworkPath,
                width: width,
                height: height,
            )
            guard !Task.isCancelled else { return }
            resource = loadedResource
            isLoading = false
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            resource = nil
            isLoading = false
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.surfaceSubtle
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.textTertiary)
        }
    }
}

func playerTimestampText(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let totalSeconds = Int(value.rounded())
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
