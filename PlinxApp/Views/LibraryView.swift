import SwiftUI
import PlinxUI

struct LibraryView: View {
    @State private var showingGate = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Library")
                    .font(.largeTitle.bold())

                LiquidGlassButton("Movies") {}
                LiquidGlassButton("TV Shows") {}
                LiquidGlassButton("Personal Videos") {}

                Spacer()

                Button("Parental Settings") {
                    showingGate = true
                }
                .padding()
                .foregroundStyle(.secondary)
            }
            .padding()
            .sheet(isPresented: $showingGate) {
                ParentalGateView {
                    showingGate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingSettings = true
                    }
                }
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}
