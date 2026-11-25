import SwiftUI
import PlinxCore
import PlinxUI

struct LibraryViewsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        List {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { settingsManager.interface.displayCollections },
                        set: { settingsManager.setDisplayCollections($0) }
                    )
                ) {
                    Label {
                        Text("settings.libraryViews.collectionButton", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "rectangle.stack.fill")
                    }
                }
            } header: {
                Text("settings.libraryViews.title", tableName: "Plinx")
            }

            Section("Libraries") {
                ForEach(librariesWithRecommendations, id: \.identity) { library in
                    NavigationLink {
                        LibraryViewSectionsConfigurationView(library: library)
                    } label: {
                        Label {
                            LibrarySettingsLabel(
                                title: library.title,
                                subtitle: libraryStore.showsServerNames ? libraryStore.serverName(for: library) : nil
                            )
                        } icon: {
                            Image(systemName: library.iconName)
                        }
                    }
                    #if os(tvOS)
                    .plinxSettingsListButton()
                    #endif
                }
            }
        }
        .navigationTitle(Text("settings.libraryViews.title", tableName: "Plinx"))
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
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
        }
    }

    /// Libraries whose detail screen has a Recommended tab to configure.
    private var librariesWithRecommendations: [Library] {
        PlinxLibraryVisibility.browsableLibraries(libraryStore.libraries).filter { library in
            LibraryDetailTab.available(
                for: library,
                provider: library.server.provider,
                displaysCollections: settingsManager.interface.displayCollections,
                displaysPlaylists: false
            ).contains(.recommended)
        }
    }
}

private struct LibraryViewSectionsConfigurationView: View {
    private struct RecommendSection: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let library: Library

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ServerRegistry.self) private var registry

    @State private var sections: [RecommendSection] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var hiddenIds: Set<String> {
        Set(settingsManager.plinxLibraryViewSettings(for: library.id).hiddenRecommendSectionIds)
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView().tint(.accentColor)
                        Spacer()
                    }
                }
            } else if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            } else if sections.isEmpty {
                Section {
                    Text("settings.libraryViews.empty", tableName: "Plinx")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    #if os(tvOS)
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        HStack {
                            Toggle(
                                isOn: Binding(
                                    get: { !hiddenIds.contains(section.id) },
                                    set: { isVisible in
                                        settingsManager.plinxSetRecommendSectionHidden(!isVisible, libraryId: library.id, sectionId: section.id)
                                    }
                                )
                            ) {
                                Text(section.title)
                            }
                            Spacer()
                            Button { moveSection(at: index, by: -1) } label: {
                                Label {
                                    Text("settings.actions.moveUp", tableName: "Plinx")
                                } icon: {
                                    Image(systemName: "arrow.up")
                                }
                            }
                            .buttonStyle(PlinxSettingsActionButtonStyle())
                            .focusEffectDisabled()
                            .disabled(index == 0)
                            .accessibilityLabel(Text("settings.actions.moveUp", tableName: "Plinx"))
                            Button { moveSection(at: index, by: 1) } label: {
                                Label {
                                    Text("settings.actions.moveDown", tableName: "Plinx")
                                } icon: {
                                    Image(systemName: "arrow.down")
                                }
                            }
                            .buttonStyle(PlinxSettingsActionButtonStyle())
                            .focusEffectDisabled()
                            .disabled(index == sections.count - 1)
                            .accessibilityLabel(Text("settings.actions.moveDown", tableName: "Plinx"))
                        }
                    }
                    #else
                    ForEach(sections) { section in
                        Toggle(
                            isOn: Binding(
                                get: { !hiddenIds.contains(section.id) },
                                set: { isVisible in
                                    settingsManager.plinxSetRecommendSectionHidden(!isVisible, libraryId: library.id, sectionId: section.id)
                                }
                            )
                        ) {
                            Text(section.title)
                        }
                    }
                    .onMove(perform: moveSections)
                    #endif
                } footer: {
                    Text("settings.libraryViews.description", tableName: "Plinx")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(library.title)
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        #endif
        .environment(\.editMode, .constant(.active))
        .plinxSettingsChrome()
        .task {
            await loadSections()
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        settingsManager.plinxSetRecommendSectionOrder(sections.map(\.id), libraryId: library.id)
    }

    private func moveSection(at index: Int, by offset: Int) {
        let destination = index + offset
        guard sections.indices.contains(index), sections.indices.contains(destination) else { return }
        sections.swapAt(index, destination)
        settingsManager.plinxSetRecommendSectionOrder(sections.map(\.id), libraryId: library.id)
    }

    /// The sections a child sees on this library's Recommended tab: the
    /// server's hubs after `SafeMediaServices` drops blocked titles, without
    /// the sections that filtering emptied.
    private func loadSections() async {
        guard let services = registry.services(for: library.server) else {
            sections = []
            errorMessage = String(localized: "server.unavailable.message")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let hubs = try await services.library.recommended(
                in: library,
                mergesNextUp: settingsManager.interface.mergesNextUpIntoContinueWatching
            )
            let filteredHubs = ContentSafetyGate.shared.filter(hubs)

            var seen = Set<String>()
            let availableSections = filteredHubs.compactMap { hub -> RecommendSection? in
                guard !hub.items.isEmpty else { return nil }
                guard !seen.contains(hub.id) else { return nil }
                seen.insert(hub.id)
                return RecommendSection(id: hub.id, title: hub.title)
            }

            let orderedIds = settingsManager.plinxResolvedRecommendSectionIds(
                for: library.id,
                availableSectionIds: availableSections.map(\.id)
            )
            let allById = Dictionary(uniqueKeysWithValues: availableSections.map { ($0.id, $0) })

            let orderedVisible = orderedIds.compactMap { allById[$0] }
            let orderedVisibleIds = Set(orderedVisible.map(\.id))
            let hiddenOrUnordered = availableSections.filter { !orderedVisibleIds.contains($0.id) }
            sections = orderedVisible + hiddenOrUnordered
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            sections = []
            errorMessage = error.localizedDescription
        }
    }
}
