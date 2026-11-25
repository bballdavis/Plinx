import SwiftUI
import PlinxCore
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreenSettingsView
//
// Controls which libraries appear in the "Recently Added" rows on the home
// screen, and in what order. These settings only narrow Home further: a
// library hidden with "Visible Libraries" is left out of Home, the Library tab
// and search whatever is stored here, so this list only offers the libraries
// the active profile shows.
//
// Libraries are identified by `LibraryIdentity.stableKey`
// (`<provider>:<serverID>:<libraryID>`), so two servers with the same library
// id never share a setting. Builds before multi-server stored the plain
// library id; `HomeLibrarySettingKeys.migrateStoredKeys` (run by Home once
// every enabled server's libraries are loaded, and by this screen) rewrites
// such an id to the stable key of the one library that has it, and keeps it
// as stored when several libraries (or none) have it.
// `HomeRecentlyAddedProjection` honors both forms, so nothing a family set is
// lost either way.
//
// Persistence keys (app-level AppStorage / UserDefaults.standard):
//   plinx.homeHiddenLibraryIds   – JSON [String]  library keys hidden from home
//   plinx.homeLibraryOrder       – JSON [String]  library keys in display order
//   plinx.homeCombineMoviesTV    – Bool            combine movies+TV into one section
// ─────────────────────────────────────────────────────────────────────────────

struct HomeScreenSettingsView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ServerRegistry.self) private var registry

    /// JSON-encoded [String] of library keys hidden from the home screen.
    @AppStorage("plinx.homeHiddenLibraryIds") private var hiddenIdsJson = "[]"
    /// JSON-encoded [String] of library keys in preferred display order.
    @AppStorage("plinx.homeLibraryOrder") private var orderJson = "[]"
    /// JSON-encoded [String] of section IDs in display order.
    @AppStorage("plinx.homeSectionOrder") private var sectionOrderJson = "[]"
    /// Whether to show movies and TV as a single combined section (default: true).
    @AppStorage("plinx.homeCombineMoviesTV") private var combineMoviesTV = true

    /// Live in-memory ordered list of libraries; initialised from stored prefs.
    @State private var orderedLibraries: [Library] = []
    /// Live in-memory ordered section IDs.
    @State private var orderedSections: [String] = []

    // MARK: - Fixed section definitions

    private var currentDefaultSectionOrder: [String] {
        combineMoviesTV
            ? ["continueWatching", "moviesAndTV", "otherVideos"]
            : ["continueWatching", "recentMovies", "recentTV", "otherVideos"]
    }

    private func sectionDisplayKey(_ id: String) -> String {
        switch id {
        case "continueWatching": return "home.section.continueWatching"
        case "moviesAndTV":      return "home.section.moviesAndTV"
        case "recentMovies":     return "home.section.recentMovies"
        case "recentTV":         return "home.section.recentTV"
        case "otherVideos":      return "home.section.otherVideos"
        default:                 return id
        }
    }

    private func sectionIconName(_ id: String) -> String {
        switch id {
        case "continueWatching": return "clock.arrow.circlepath"
        case "moviesAndTV":      return "film.fill"
        case "recentMovies":     return "film.fill"
        case "recentTV":         return "tv.fill"
        case "otherVideos":      return "video.fill"
        default:                 return "square.grid.2x2"
        }
    }

    // MARK: - Computed helpers

    private var hiddenIds: Set<String> {
        Set(decodeStringArray(hiddenIdsJson))
    }

    private func isHidden(_ library: Library) -> Bool {
        let hidden = hiddenIds
        return HomeLibrarySettingKeys.keys(for: library).contains(where: hidden.contains)
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: Combine Movies & TV toggle
            Section {
                Toggle(isOn: $combineMoviesTV) {
                    Label(
                        String(localized: "settings.homescreen.combine.label", table: "Plinx"),
                        systemImage: "film.stack"
                    )
                }
            } footer: {
                Text("settings.homescreen.combine.footer", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Section order
            Section {
                #if os(tvOS)
                ForEach(Array(orderedSections.enumerated()), id: \.element) { index, sectionId in
                    HStack {
                        Label {
                            Text(LocalizedStringKey(sectionDisplayKey(sectionId)), tableName: "Plinx")
                        } icon: {
                            Image(systemName: sectionIconName(sectionId))
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
                        .disabled(index == orderedSections.count - 1)
                        .accessibilityLabel(Text("settings.actions.moveDown", tableName: "Plinx"))
                    }
                }
                #else
                ForEach(orderedSections, id: \.self) { sectionId in
                    Label {
                        Text(LocalizedStringKey(sectionDisplayKey(sectionId)), tableName: "Plinx")
                    } icon: {
                        Image(systemName: sectionIconName(sectionId))
                    }
                }
                .onMove { indices, newOffset in
                    orderedSections.move(fromOffsets: indices, toOffset: newOffset)
                    sectionOrderJson = encodeStringArray(orderedSections)
                }
                #endif
            } header: {
                Text("settings.homescreen.sections.title", tableName: "Plinx")
            } footer: {
                Text("settings.homescreen.sections.footer", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Recently Added library visibility & order
            Section {
                ForEach(orderedLibraries, id: \.identity) { library in
                    HomeLibraryRow(
                        library: library,
                        isEnabled: !isHidden(library),
                        onToggle: { enabled in
                            toggle(library: library, enabled: enabled)
                        }
                    )
                }
            } header: {
                Label {
                    Text("settings.homescreen.recentlyadded.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "clock.fill")
                }
            } footer: {
                Text("settings.homescreen.recentlyadded.footer", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("settings.homescreen.title", tableName: "Plinx"))
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        #endif
        .environment(\.editMode, .constant(.active))
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.appBackground.ignoresSafeArea())
        .plinxSettingsChrome()
        .task {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
            migrateLegacyLibraryKeys()
            buildOrderedList()
            buildSectionOrder()
        }
        .onChange(of: libraryStore.visibleLibraries) { _, _ in
            migrateLegacyLibraryKeys()
            buildOrderedList()
        }
        .onChange(of: combineMoviesTV) { _, newValue in
            migrateAndRebuildSectionOrder(combining: newValue)
        }
    }

    // MARK: - Helpers

    /// Merge stored order with actual libraries (handles new libraries added to server).
    private func buildOrderedList() {
        let all = PlinxLibraryVisibility.browsableLibraries(libraryStore.visibleLibraries)
        let storedOrder = decodeStringArray(orderJson)

        if storedOrder.isEmpty {
            orderedLibraries = all
        } else {
            // Put stored-order libraries first, then append any new ones not in stored order.
            var placed = Set<LibraryIdentity>()
            let ordered = storedOrder.flatMap { key in
                all.filter { HomeLibrarySettingKeys.keys(for: $0).contains(key) && placed.insert($0.identity).inserted }
            }
            let extras = all.filter { !placed.contains($0.identity) }
            orderedLibraries = ordered + extras
        }
    }

    private func migrateLegacyLibraryKeys() {
        HomeLibrarySettingKeys.migrateStoredKeys(
            hiddenJSON: $hiddenIdsJson,
            orderJSON: $orderJson,
            libraryStore: libraryStore,
            registry: registry
        )
    }

    /// Build the ordered section list, filling in any missing defaults at the end.
    private func buildSectionOrder() {
        let stored = decodeStringArray(sectionOrderJson)
        let defaults = currentDefaultSectionOrder
        if stored.isEmpty {
            orderedSections = defaults
        } else {
            let storedKnown = stored.filter { defaults.contains($0) }
            let missing = defaults.filter { !Set(stored).contains($0) }
            orderedSections = storedKnown + missing
        }
    }

    /// Migrate the in-memory section order when the combine toggle changes,
    /// swapping between "moviesAndTV" and the discrete "recentMovies"/"recentTV" IDs.
    private func migrateAndRebuildSectionOrder(combining: Bool) {
        if combining {
            // Collapse recentMovies / recentTV → moviesAndTV at the position of the first one found.
            var result: [String] = []
            var insertedCombined = false
            for section in orderedSections {
                if section == "recentMovies" || section == "recentTV" {
                    if !insertedCombined {
                        result.append("moviesAndTV")
                        insertedCombined = true
                    }
                } else {
                    result.append(section)
                }
            }
            if !insertedCombined { result.append("moviesAndTV") }
            orderedSections = result
        } else {
            // Expand moviesAndTV → recentMovies + recentTV.
            var result: [String] = []
            for section in orderedSections {
                if section == "moviesAndTV" {
                    result.append("recentMovies")
                    result.append("recentTV")
                } else {
                    result.append(section)
                }
            }
            orderedSections = result
        }
        sectionOrderJson = encodeStringArray(orderedSections)
    }

    private func toggle(library: Library, enabled: Bool) {
        var keys = Set(decodeStringArray(hiddenIdsJson))
        let key = HomeLibrarySettingKeys.key(for: library)
        if enabled {
            keys.remove(key)
            if keys.remove(library.id) != nil {
                // A plain id kept because several libraries share it hid all
                // of them: the others stay hidden under their own keys.
                for other in libraryStore.libraries where other.id == library.id && other.identity != library.identity {
                    keys.insert(HomeLibrarySettingKeys.key(for: other))
                }
            }
        } else {
            keys.insert(key)
        }
        hiddenIdsJson = encodeStringArray(Array(keys).sorted())
    }

    private func moveSection(at index: Int, by offset: Int) {
        let destination = index + offset
        guard orderedSections.indices.contains(index), orderedSections.indices.contains(destination) else { return }
        orderedSections.swapAt(index, destination)
        sectionOrderJson = encodeStringArray(orderedSections)
    }

}

// MARK: - Library keys

/// Keys of the Home library settings (`plinx.homeHiddenLibraryIds`,
/// `plinx.homeLibraryOrder`). New values are `LibraryIdentity.stableKey`;
/// plain library ids written before multi-server are still read.
enum HomeLibrarySettingKeys {
    /// The key written for `library`.
    static func key(for library: Library) -> String {
        library.identity.stableKey
    }

    /// Every stored form that refers to `library`: its stable key, then the
    /// plain library id of single-server builds.
    static func keys(for library: Library) -> [String] {
        HomeRecentlyAddedProjection.settingKeys(for: library)
    }

    /// Replaces each plain library id by the stable key of the one library in
    /// `libraries` with that id, keeping order and dropping duplicates. An id
    /// that several libraries share, or none, stays as stored.
    static func migrated(_ stored: [String], libraries: [Library]) -> [String] {
        var seen = Set<String>()
        return stored.compactMap { value in
            var resolved = value
            if LibraryIdentity(stableKey: value) == nil {
                let matches = libraries.filter { $0.id == value }
                if matches.count == 1 {
                    resolved = key(for: matches[0])
                }
            }
            return seen.insert(resolved).inserted ? resolved : nil
        }
    }

    /// Rewrites the plain library ids stored before multi-server in both
    /// settings to stable keys, once every enabled server's libraries are
    /// known: an id is only unambiguous when no server is missing from the
    /// comparison. Writes only what changes. Home runs it as libraries load,
    /// so families' settings migrate without opening this screen.
    @MainActor
    static func migrateStoredKeys(
        hiddenJSON: Binding<String>,
        orderJSON: Binding<String>,
        libraryStore: LibraryStore,
        registry: ServerRegistry
    ) {
        let enabledServers = Set(registry.enabledSessions.map(\.identity))
        guard !enabledServers.isEmpty,
              enabledServers.isSubset(of: libraryStore.librariesByServer.keys)
        else { return }
        let libraries = libraryStore.libraries
        let hidden = decodeStringArray(hiddenJSON.wrappedValue)
        let migratedHidden = migrated(hidden, libraries: libraries)
        if migratedHidden != hidden {
            hiddenJSON.wrappedValue = encodeStringArray(migratedHidden.sorted())
        }
        let order = decodeStringArray(orderJSON.wrappedValue)
        let migratedOrder = migrated(order, libraries: libraries)
        if migratedOrder != order {
            orderJSON.wrappedValue = encodeStringArray(migratedOrder)
        }
    }
}

// MARK: - Row

private struct HomeLibraryRow: View {
    let library: Library
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isEnabled }, set: { onToggle($0) })) {
            Label(library.title, systemImage: library.iconName)
        }
    }
}

// MARK: - JSON helpers

private func decodeStringArray(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return arr
}

private func encodeStringArray(_ arr: [String]) -> String {
    guard let data = try? JSONEncoder().encode(arr),
          let str = String(data: data, encoding: .utf8)
    else { return "[]" }
    return str
}
