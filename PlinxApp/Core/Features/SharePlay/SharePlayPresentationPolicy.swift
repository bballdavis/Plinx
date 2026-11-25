import SwiftUI

/// Whether screens may offer to start SharePlay.
///
/// Starting SharePlay opens a FaceTime or Messages group activity with people
/// outside the app, so kid-facing UI never offers it. The default is `.hidden`
/// (fail closed): only a parent-facing surface may set `.enabled`. Media a
/// joined session asks for still goes through the safe services and the
/// player's final authorization check.
enum SharePlayPresentationPolicy: Sendable {
    case enabled
    case hidden
}

extension EnvironmentValues {
    @Entry var sharePlayPresentationPolicy: SharePlayPresentationPolicy = .hidden
}
