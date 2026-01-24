import SwiftUI
import PlinxUI

struct LibraryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Library")
                .font(.largeTitle.bold())

            LiquidGlassButton("Movies") {}
            LiquidGlassButton("TV Shows") {}
            LiquidGlassButton("Personal Videos") {}
        }
        .padding()
    }
}
