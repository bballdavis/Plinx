import SwiftUI

@MainActor
struct SettingsDownloadsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        List {
            Section {
                Toggle(
                    String(localized: "settings.downloads.wifiOnly", table: "Plinx"),
                    isOn: Binding(
                        get: { settingsManager.downloads.wifiOnly },
                        set: { settingsManager.setDownloadWiFiOnly($0) }
                    )
                )
            } footer: {
                Text("settings.downloads.wifiOnly.footer", tableName: "Plinx")
            }

            Section {
                Picker(
                    String(localized: "settings.downloads.quality", table: "Plinx"),
                    selection: Binding(
                        get: { settingsManager.downloads.quality },
                        set: { settingsManager.setDownloadQuality($0) }
                    )
                ) {
                    ForEach(DownloadQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                #if !os(tvOS)
                .pickerStyle(.navigationLink)
                #endif
            } header: {
                Text("settings.downloads.quality", tableName: "Plinx")
            } footer: {
                Text("settings.downloads.quality.description", tableName: "Plinx")
            }
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(Text("settings.downloads.title", tableName: "Plinx"))
    }
}
