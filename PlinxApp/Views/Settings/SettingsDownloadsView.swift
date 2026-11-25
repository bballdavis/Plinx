import SwiftUI

/// Download preferences, reached from protected Settings (and from the absorbed
/// `SettingsView`): Wi-Fi only and the default download quality. Lower presets
/// ask the server for a smaller transcode; `DownloadSpaceSavingsPolicy` keeps
/// the original file when the transcode would not save space.
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
                .accessibilityIdentifier("settings.downloads.wifiOnly")
            } footer: {
                Text("settings.downloads.wifiOnly.footer", tableName: "Plinx")
            }

            Section {
                Picker(
                    String(localized: "settings.downloads.quality", table: "Plinx"),
                    selection: Binding(
                        get: { settingsManager.downloads.qualityPreset },
                        set: { settingsManager.setDownloadQualityPreset($0) }
                    )
                ) {
                    ForEach(TranscodeQualityPreset.displayOrder) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .accessibilityIdentifier("settings.downloads.quality")
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
        .plinxSettingsChrome()
    }
}
