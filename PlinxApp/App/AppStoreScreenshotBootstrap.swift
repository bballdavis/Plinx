import SwiftUI
import UIKit

/// UI-test-only entry points for capturing production views against the local
/// fixture service. This type supplies initial data but does not own a visual
/// implementation.
enum AppStoreScreenshotBootstrap {
    static let mediaDetailScreen = "appStoreMediaDetail"
    private static let landscapeArgument = "--app-store-landscape"
    private static let releaseLandscapeArgument = "--release-screenshot-landscape"

    static func requestsLandscape(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains(landscapeArgument) || arguments.contains(releaseLandscapeArgument)
    }

    @MainActor
    static func applyRequestedOrientation(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        guard requestsLandscape(arguments: arguments) else {
            return
        }
        #if os(iOS)
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

    static var media: PlayableMediaItem {
        PlayableMediaItem(
            mediaItem: MediaItem(
                id: "moonbound",
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
                ultraBlurColors: nil,
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
        )!
    }
}

struct AppStoreMediaDetailScreenshotHarness: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.safetyPolicy) private var safetyPolicy

    var body: some View {
        if sessionManager.status == .ready {
            NavigationStack {
                PlinxMediaDetailView(
                    viewModel: SafeMediaDetailViewModel(
                        inner: MediaDetailViewModel(
                            media: AppStoreScreenshotBootstrap.media,
                            context: plexApiContext
                        ),
                        policy: safetyPolicy
                    ),
                    onPlay: { _, _ in },
                    onShuffle: { _, _ in },
                    onSelectRelated: { _ in }
                )
            }
        } else {
            PlinxBrandedLoadingView(context: .appTransition)
        }
    }
}
