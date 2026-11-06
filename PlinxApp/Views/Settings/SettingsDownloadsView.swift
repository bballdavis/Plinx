import SwiftUI

@MainActor
struct SettingsDownloadsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        List {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { settingsManager.downloads.wifiOnly },
                        set: { settingsManager.setDownloadWiFiOnly($0) }
                    )
                ) {
                    Label {
                        Text("settings.downloads.wifiOnly", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "wifi")
                    }
                }
            } footer: {
                Text("settings.downloads.wifiOnly.footer", tableName: "Plinx")
            }

            Section {
                NavigationLink {
                    PlinxSettingsChoiceView(
                        title: Text("settings.downloads.quality", tableName: "Plinx"),
                        choices: DownloadQuality.allCases.map {
                            PlinxSettingsChoice(value: $0, title: $0.title)
                        },
                        selection: qualityBinding,
                        footer: Text("settings.downloads.quality.description", tableName: "Plinx"),
                        accessibilityPrefix: "settings.downloads.quality"
                    )
                } label: {
                    PlinxSettingsValueLabel(
                        title: Text("settings.downloads.quality", tableName: "Plinx"),
                        systemImage: "dial.medium.fill",
                        value: settingsManager.downloads.quality.title
                    )
                }
            } footer: {
                Text("settings.downloads.quality.description", tableName: "Plinx")
            }
        }
        .plinxSettingsPage(title: Text("settings.downloads.title", tableName: "Plinx"))
    }

    private var qualityBinding: Binding<DownloadQuality> {
        Binding(
            get: { settingsManager.downloads.quality },
            set: { settingsManager.setDownloadQuality($0) }
        )
    }
}
