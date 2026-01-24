import SwiftUI
import PlinxCore

public struct LiquidGlassButton: View {
    private let title: String
    private let action: () -> Void
    private let haptics: HapticManaging
    private let audio: PlinkAudioManaging
    private let theme: PlinxTheme

    public init(
        _ title: String,
        theme: PlinxTheme = PlinxTheme(),
        haptics: HapticManaging = HapticManager(),
        audio: PlinkAudioManaging = PlinkAudioManager(),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.theme = theme
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
                .liquidGlassStyle(theme: theme)
        }
        .buttonStyle(.plain)
    }
}
