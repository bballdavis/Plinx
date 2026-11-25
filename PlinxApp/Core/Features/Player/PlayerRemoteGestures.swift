import Foundation

/// What a center click does while the tvOS player controls are hidden.
enum PlayerCenterClickResult: Equatable {
    /// A contextual action such as "Skip Intro" holds the focus and handles the click itself.
    case activateContextualAction
    case resumeFromPauseScreen
    case togglePlayPause
    case showControls

    static func resolve(
        setting: PlayerCenterClickAction,
        hasContextualAction: Bool,
        isPauseScreenPresented: Bool,
    ) -> PlayerCenterClickResult {
        if hasContextualAction {
            return .activateContextualAction
        }
        if isPauseScreenPresented {
            return .resumeFromPauseScreen
        }
        switch setting {
        case .playPause: return .togglePlayPause
        case .showControls: return .showControls
        }
    }
}
