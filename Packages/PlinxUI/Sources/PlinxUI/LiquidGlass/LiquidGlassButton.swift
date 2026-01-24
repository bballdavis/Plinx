import SwiftUI
import PlinxCore

public struct LiquidGlassButton: View {
    private let title: String
    private let action: () -> Void
    private let haptics: HapticManaging
    private let audio: PlinkAudioManaging

    public init(
        _ title: String,
        haptics: HapticManaging = HapticManager(),
        audio: PlinkAudioManaging = PlinkAudioManager(),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.haptics = haptics
        self.audio = audio
        self.action = action
    }

    public var body: some View {
        Button(action: {
            audio.playPlink()
            haptics.plink()
            action()
        }) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: .white.opacity(0.35), radius: 10, x: -4, y: -6)
                        .shadow(color: .black.opacity(0.2), radius: 12, x: 6, y: 8)
                )
        }
        .buttonStyle(.plain)
    }
}
