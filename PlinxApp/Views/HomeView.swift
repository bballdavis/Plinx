import SwiftUI
import PlinxUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Continue Watching")
                        .font(.title2.bold())

                    LiquidGlassButton("Resume") {}

                    Text("Recommended")
                        .font(.title2.bold())

                    LiquidGlassButton("Play Next") {}
                }
                .padding()
            }
            .navigationTitle("Plinx")
        }
    }
}
