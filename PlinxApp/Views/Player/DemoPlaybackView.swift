import Foundation
import PlinxUI
import SwiftUI

/// A deterministic playback surface for App Review's demo path.
///
/// The fixture has no real media server or copyrighted video. This keeps the
/// review path credential-free while still exercising the production queue,
/// authorization, detail, and playback presentation flow.
struct DemoPlaybackView: View {
    let playQueue: PlayQueueState
    let onExit: () -> Void

    @State private var isPlaying = false
    @State private var progress = 0.34

    private var item: PlexItem? {
        if let selected = playQueue.selectedRatingKey {
            return playQueue.items.first(where: { $0.ratingKey == selected })
        }
        return playQueue.items.first
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.10, blue: 0.14), .black],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Button(action: onExit) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityIdentifier("demo.player.close")

                    Spacer()

                    Text(item?.contentRating ?? "PG")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.14), in: Capsule())
                }

                Spacer()

                Image(systemName: isPlaying ? "play.rectangle.fill" : "play.rectangle")
                    .font(.system(size: 86, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(item?.title ?? "Demo video")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("player.demo.synthetic", tableName: "Plinx")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    Slider(value: $progress)
                        .tint(Color.accentColor)
                        .accessibilityIdentifier("demo.player.progress")
                    HStack {
                        Text(progressText)
                        Spacer()
                        Text("10:12")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
                }

                Button {
                    isPlaying.toggle()
                } label: {
                    Label(
                        isPlaying ? "player.demo.pause" : "player.demo.play",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                    )
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Color.accentColor.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityIdentifier("demo.player.playPause")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 680)
        }
        .preferredColorScheme(.dark)
    }

    private var progressText: String {
        let seconds = Int(progress * 612)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
