// ─────────────────────────────────────────────────────────────────────────────
// PlinxPlayerFactory.swift — Actor-safe replacement for Strimr PlayerFactory
// ─────────────────────────────────────────────────────────────────────────────
//
// Strimr's PlayerFactory.swift has nonisolated static methods that call
// @MainActor-isolated initializers (MPVPlayerView.Coordinator(), etc.)
// which is a hard error in Swift 6.2.
//
// Fix: mark the static methods @MainActor.
//
// Upstream PR: mark PlayerFactory methods @MainActor
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftUI

enum PlayerFactory {
    @MainActor
    static func makeCoordinator(
        for selection: InternalPlaybackPlayer,
        options: PlayerOptions
    ) -> any PlayerCoordinating {
        switch selection {
        case .mpv:
            let coordinator = MPVPlayerView.Coordinator()
            coordinator.options = options
            return coordinator
        case .vlc:
            let coordinator = VLCPlayerView.Coordinator()
            coordinator.options = options
            return coordinator
        }
    }

    @MainActor
    static func makeView(
        selection: InternalPlaybackPlayer,
        coordinator: any PlayerCoordinating,
        onPropertyChange: @escaping (PlayerProperty, Any?) -> Void,
        onPlaybackEnded: @escaping () -> Void,
        onMediaLoaded: @escaping () -> Void
    ) -> AnyView {
        switch selection {
        case .mpv:
            guard let mpvCoordinator = coordinator as? MPVPlayerView.Coordinator else {
                assertionFailure("MPV coordinator expected")
                return AnyView(EmptyView())
            }
            return AnyView(
                MPVPlayerView(coordinator: mpvCoordinator)
                    .onPropertyChange { _, property, data in
                        onPropertyChange(property, data)
                    }
                    .onPlaybackEnded(onPlaybackEnded)
                    .onMediaLoaded(onMediaLoaded)
            )
        case .vlc:
            guard let vlcCoordinator = coordinator as? VLCPlayerView.Coordinator else {
                assertionFailure("VLC coordinator expected")
                return AnyView(EmptyView())
            }
            return AnyView(
                VLCPlayerView(coordinator: vlcCoordinator)
                    .onPropertyChange { _, property, data in
                        onPropertyChange(property, data)
                    }
                    .onPlaybackEnded(onPlaybackEnded)
                    .onMediaLoaded(onMediaLoaded)
            )
        }
    }
}
