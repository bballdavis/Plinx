import Foundation
@testable import Plinx
import Testing

@MainActor
struct PlayerRemoteGesturesTests {
    @Test func `center click follows the setting while nothing else claims it`() {
        #expect(resolve(.playPause) == .togglePlayPause)
        #expect(resolve(.showControls) == .showControls)
    }

    @Test func `contextual action takes the click before the setting and the pause screen`() {
        #expect(resolve(.playPause, contextual: true, pauseScreen: true) == .activateContextualAction)
        #expect(resolve(.showControls, contextual: true) == .activateContextualAction)
    }

    @Test func `center click on the pause screen resumes whatever the setting`() {
        #expect(resolve(.playPause, pauseScreen: true) == .resumeFromPauseScreen)
        #expect(resolve(.showControls, pauseScreen: true) == .resumeFromPauseScreen)
    }

    private func resolve(
        _ setting: PlayerCenterClickAction,
        contextual: Bool = false,
        pauseScreen: Bool = false,
    ) -> PlayerCenterClickResult {
        PlayerCenterClickResult.resolve(
            setting: setting,
            hasContextualAction: contextual,
            isPauseScreenPresented: pauseScreen,
        )
    }
}
