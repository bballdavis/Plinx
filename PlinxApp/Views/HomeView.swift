import SwiftUI
import PlinxUI

struct HomeView: View {
    @State private var playingMedia = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Continue Watching")
                        .font(.title2.bold())

                    LiquidGlassButton("Resume") {
                        playingMedia = true
                    }

                    Text("Recommended")
                        .font(.title2.bold())

                    LiquidGlassButton("Play Next") {
                        playingMedia = true
                    }
                }
                .padding()
            }
            .navigationTitle("Plinx")
            .fullScreenCover(isPresented: $playingMedia) {
                PlayerView()
            }
        }
    }
}
