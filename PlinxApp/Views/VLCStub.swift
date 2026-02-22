import SwiftUI

struct VLCPlayerView: View {
    let coordinator: Coordinator
    
    @MainActor
    final class Coordinator: PlayerCoordinating {
        var options = PlayerOptions()
        func play(_ url: URL) {}
        func togglePlayback() {}
        func pause() {}
        func resume() {}
        func seek(to time: Double) {}
        func seek(by delta: Double) {}
        func selectAudioTrack(id: Int?) {}
        func selectSubtitleTrack(id: Int?) {}
        func trackList() -> [PlayerTrack] { [] }
        func destruct() {}
    }
    
    var body: some View {
        ZStack {
            Color.black
            Text("player.vlc.missing", tableName: "Plinx")
                .foregroundStyle(.white)
        }
    }
    
    func onPropertyChange(_ action: @escaping (VLCPlayerView, PlayerProperty, Any?) -> Void) -> VLCPlayerView { self }
    func onPlaybackEnded(_ action: @escaping () -> Void) -> VLCPlayerView { self }
    func onMediaLoaded(_ action: @escaping () -> Void) -> VLCPlayerView { self }
}
