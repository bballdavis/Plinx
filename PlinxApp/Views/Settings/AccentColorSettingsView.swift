import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// AccentColorSettingsView
//
// Lets the user pick one of 8 preset accent colors.  The choice is stored in
// AppStorage under "plinx.accentColorName" and propagated as a root .tint()
// in PlinxApp, making the change immediate and app-wide.
// ─────────────────────────────────────────────────────────────────────────────

struct AppearanceSettingsView: View {
    @AppStorage("plinx.chromeButtonSize") private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue
    @AppStorage(PlinxAnimationPreference.playfulAnimationsStorageKey)
    private var playfulAnimationsEnabled = PlinxAnimationPreference.defaultPlayfulAnimationsEnabled

    private var chromeButtonSize: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .medium
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { chromeButtonSize.sliderIndex },
            set: { chromeButtonSizeRaw = PlinxChromeButtonSizePreference.from(sliderIndex: $0).rawValue }
        )
    }

    var body: some View {
        List {
            Section {
                NavigationLink(destination: AccentColorSettingsView()) {
                    Label {
                        Text("settings.accent.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } footer: {
                Text("settings.appearance.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("settings.appearance.buttons.title", tableName: "Plinx")
                        Spacer()
                        Text(chromeButtonSize.localizedLabel)
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: sliderBinding, in: 0...2, step: 1)
                        .tint(.accentColor)

                    HStack {
                        Text("settings.appearance.buttons.small", tableName: "Plinx")
                        Spacer()
                        Text("settings.appearance.buttons.medium", tableName: "Plinx")
                        Spacer()
                        Text("settings.appearance.buttons.large", tableName: "Plinx")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("settings.appearance.buttons.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $playfulAnimationsEnabled) {
                    Label {
                        Text("settings.appearance.animations.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } footer: {
                Text("settings.appearance.animations.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("settings.appearance.title", tableName: "Plinx"))
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
    }
}

struct AccentColorSettingsView: View {
    @AppStorage("plinx.accentColorName") private var accentColorName = PlinxAccentColor.green.rawValue

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 16)]

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(PlinxAccentColor.allCases) { option in
                        colorSwatch(option)
                    }
                }
                .padding(.vertical, 8)
            } footer: {
                Text("settings.accent.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("settings.accent.title", tableName: "Plinx"))
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
    }

    private func colorSwatch(_ option: PlinxAccentColor) -> some View {
        let isSelected = accentColorName == option.rawValue
        return Button {
            accentColorName = option.rawValue
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(option.color)
                        .frame(width: 48, height: 48)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? option.color : Color.white.opacity(0.2),
                            lineWidth: isSelected ? 3 : 1
                        )
                        .padding(-4)
                )

                Text(option.label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? option.color : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
