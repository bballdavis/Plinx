import SwiftUI
import PlinxCore
import PlinxUI

/// Shows a toggle for each library of the active profile. Libraries toggled
/// OFF are hidden from the Library tab and left out of Home and search
/// (`PlinxLibraryVisibility`). The choice is stored per profile in upstream's
/// `LibraryPreferences.hiddenLibraries`, so every server's libraries are kept
/// apart; older single-server settings were moved there by `MultiServerMigration`.
struct VisibleLibrariesView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    private var displayedLibraries: DisplayedLibrariesViewModel {
        DisplayedLibrariesViewModel(settingsManager: settingsManager, libraryStore: libraryStore)
    }

    var body: some View {
        let viewModel = displayedLibraries

        List {
            if viewModel.libraries.isEmpty {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(.accentColor)
                        Spacer()
                    }
                } else {
                    Text("settings.libraries.noneFound", tableName: "Plinx")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(viewModel.libraries, id: \.identity) { library in
                        Toggle(isOn: viewModel.displayedBinding(for: library)) {
                            Label {
                                LibrarySettingsLabel(title: library.title, subtitle: viewModel.subtitle(for: library))
                            } icon: {
                                Image(systemName: library.iconName)
                            }
                        }
                    }
                } footer: {
                    Text("settings.libraries.description", tableName: "Plinx")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("settings.libraries.screen")
        .navigationTitle(Text("settings.libraries.title", tableName: "Plinx"))
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.appBackground.ignoresSafeArea())
        .plinxSettingsChrome()
        .task {
            await viewModel.loadLibraries()
        }
    }
}
