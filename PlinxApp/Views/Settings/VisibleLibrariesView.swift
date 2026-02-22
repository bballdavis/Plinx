import SwiftUI
import PlinxCore

/// Shows a toggle for each library. Libraries toggled OFF are hidden from
/// the Library tab AND excluded from the home-screen hub fetch.
struct VisibleLibrariesView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        List {
            if libraryStore.libraries.isEmpty {
                Text("No libraries found.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(libraryStore.libraries) { library in
                        LibraryVisibilityRow(library: library, settingsManager: settingsManager)
                    }
                } footer: {
                    Text("settings.libraries.description", tableName: "Plinx")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Visible Libraries")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .task {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
        }
    }
}

// MARK: - Row

private struct LibraryVisibilityRow: View {
    let library: Library
    let settingsManager: SettingsManager

    private var isVisible: Bool {
        !settingsManager.interface.hiddenLibraryIds.contains(library.id)
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isVisible },
            set: { show in
                settingsManager.setLibraryDisplayed(library.id, displayed: show)
            }
        )) {
            Label(library.title, systemImage: library.iconName)
        }
        .tint(.orange)
    }
}
