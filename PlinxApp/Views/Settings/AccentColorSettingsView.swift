import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// AccentColorSettingsView
//
// Lets the user pick one of 8 preset accent colors.  The choice is stored in
// AppStorage under "plinx.accentColorName" and propagated as a root .tint()
// in PlinxApp, making the change immediate and app-wide.
// ─────────────────────────────────────────────────────────────────────────────

struct AccentColorSettingsView: View {
    @AppStorage("plinx.accentColorName") private var accentColorName = PlinxAccentColor.orange.rawValue

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
