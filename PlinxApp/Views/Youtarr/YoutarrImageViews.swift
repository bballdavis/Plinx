import SwiftUI
import PlinxCore
import PlinxUI

struct YoutarrMetadataBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct YoutarrThumbnailView: View {
    let rawURL: String?
    let configuration: YoutarrConfiguration
    let aspectRatio: CGFloat

    var body: some View {
        Group {
            switch YoutarrAssetRequestPolicy.route(
                rawURL: rawURL,
                configuration: configuration
            ) {
            case .authenticated(let request):
                YoutarrAuthenticatedImageView(request: request)
            case .unavailable:
                placeholder
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.16)
            Image(systemName: "play.rectangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct YoutarrAuthenticatedImageView: View {
    let request: URLRequest
    @StateObject private var loader = YoutarrAuthenticatedImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.16)
                    if loader.didFail {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .task(id: request.url) {
            await loader.load(request)
        }
    }
}
