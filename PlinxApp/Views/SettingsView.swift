import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Libraries") {
                Toggle("Movies", isOn: .constant(true))
                Toggle("TV Shows", isOn: .constant(true))
                Toggle("Personal Videos", isOn: .constant(false))
            }

            Section("Content Rating") {
                Picker("Max Rating", selection: .constant("G")) {
                    Text("TV-Y").tag("TV-Y")
                    Text("G").tag("G")
                    Text("TV-Y7").tag("TV-Y7")
                }
            }

            Section("Compliance") {
                Text("Source code link appears here behind parental gate.")
            }
        }
        .navigationTitle("Settings")
    }
}
