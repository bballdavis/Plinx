import SwiftUI
import PlinxCore

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
                    Label("Collection Button", systemImage: "rectangle.stack.fill")
                }
            } header: {
                Text("Library Views")
            }

            Section("Libraries") {
                ForEach(libraryStore.libraries) { library in
                    NavigationLink {
                        LibraryViewSectionsConfigurationView(library: library)
                    } label: {
                        Label(library.title, systemImage: library.iconName)
                    }
                }
            }
        }
        .navigationTitle("Library Views")
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

private struct LibraryViewSectionsConfigurationView: View {
    private struct RecommendSection: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let library: Library

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.safetyPolicy) private var safetyPolicy

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
                        ProgressView()
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
                    Text("No recommend sections available.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
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
                } footer: {
                    Text("Toggle sections on/off and drag to reorder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(library.title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .task {
            await loadSections()
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        settingsManager.plinxSetRecommendSectionOrder(sections.map(\.id), libraryId: library.id)
    }

    private func loadSections() async {
        guard let sectionId = library.sectionId else {
            sections = []
            errorMessage = String(localized: "errors.missingLibraryIdentifier")
            return
        }
        guard let hubRepository = try? HubRepository(context: plexApiContext) else {
            sections = []
            errorMessage = String(localized: "errors.selectServer.loadRecommendations")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await hubRepository.getSectionHubs(sectionId: sectionId)
            let filteredHubs = (response.mediaContainer.hub ?? [])
                .map(Hub.init)
                .compactMap { StrimrAdapter.filtered($0, policy: safetyPolicy) }

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
            sections = []
            errorMessage = error.localizedDescription
        }
    }
}
