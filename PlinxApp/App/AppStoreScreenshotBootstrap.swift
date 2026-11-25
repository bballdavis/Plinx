import SwiftUI
import UIKit

/// UI-test-only entry points for capturing production views against the local
/// fixture service. This type supplies initial data but does not own a visual
/// implementation. The landscape launch arguments work in Debug builds only.
enum AppStoreScreenshotBootstrap {
    static let mediaDetailScreen = "appStoreMediaDetail"
    private static let landscapeArgument = "--app-store-landscape"
    private static let releaseLandscapeArgument = "--release-screenshot-landscape"

    static func requestsLandscape(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        return arguments.contains(landscapeArgument) || arguments.contains(releaseLandscapeArgument)
        #else
        return false
        #endif
    }

    @MainActor
    static func applyRequestedOrientation(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        #if DEBUG && os(iOS)
        guard requestsLandscape(arguments: arguments) else {
            return
        }
        AppDelegate.orientationLock = .landscapeLeft
        // Simulator launch arguments do not emit a physical rotation event.
        // Nudge UIKit once so the production scene renders landscape before
        // the capture script takes its framebuffer screenshot.
        UIDevice.current.setValue(
            UIInterfaceOrientation.landscapeLeft.rawValue,
            forKey: "orientation"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            AppDelegate.requestCurrentGeometryUpdate()
        }
        #endif
    }

    /// The "Moonbound" sample title on `server`. The detail screen loads the rest of its metadata from the server.
    static func media(server: ServerIdentity) -> PlayableMediaItem? {
        PlayableMediaItem(
            mediaItem: MediaItem(
                id: "moonbound",
                identity: MediaIdentity(server: server, itemID: "moonbound"),
                guid: "plex://fixture/moonbound",
                summary: "A family science adventure.",
                title: "Moonbound",
                type: .movie,
                parentRatingKey: nil,
                grandparentRatingKey: nil,
                genres: ["Family", "Adventure"],
                year: 2026,
                duration: 6_120,
                videoResolution: "1080",
                rating: 8.1,
                ratings: [],
                contentRating: "PG",
                studio: "Plinx Fixture Studio",
                tagline: "Curiosity starts close to home.",
                thumbPath: "/artwork/poster/moonbound.png",
                artPath: "/artwork/backdrop/moonbound.png",
                artworkCornerColors: nil,
                viewOffset: nil,
                viewCount: nil,
                childCount: nil,
                leafCount: nil,
                viewedLeafCount: nil,
                grandparentTitle: nil,
                parentTitle: nil,
                parentIndex: nil,
                index: nil,
                grandparentThumbPath: nil,
                grandparentArtPath: nil,
                parentThumbPath: nil
            )
        )
    }
}

/// The production media detail screen for "Moonbound", shown with the services of the session's server (the
/// fixture server of the screenshot scripts) once it is connected.
struct AppStoreMediaDetailScreenshotHarness: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry

    var body: some View {
        if sessionManager.status == .ready,
           let server = registry.connectedServices.first?.identity,
           let media = AppStoreScreenshotBootstrap.media(server: server) {
            NavigationStack {
                ServerScopedView(server: server) { services in
                    PlinxMediaDetailView(
                        viewModel: MediaDetailViewModel(
                            media: media,
                            services: services,
                            resolutionMode: .selectedMedia
                        ),
                        onPlay: { _, _ in },
                        onShuffle: { _, _ in },
                        onSelectRelated: { _ in }
                    )
                }
            }
            .id(server)
        } else {
            PlinxBrandedLoadingView(context: .appTransition)
        }
    }
}
