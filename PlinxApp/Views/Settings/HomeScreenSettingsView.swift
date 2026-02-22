import SwiftUI
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreenSettingsView
//
// Controls which libraries appear in the "Recently Added" rows on the home
// screen, and in what order. Settings are stored independently from the
// "Visible Libraries" toggle so users can, e.g., hide a library from the
// Library tab while still showing it on the home screen.
//
// Persistence keys (app-level AppStorage / UserDefaults.standard):
//   plinx.homeHiddenLibraryIds  – JSON [String]  library IDs hidden from home
//   plinx.homeLibraryOrder      – JSON [String]  library IDs in display order
// ─────────────────────────────────────────────────────────────────────────────

struct HomeScreenSettingsView: View {
    @Environment(LibraryStore.self) private var libraryStore

    /// JSON-encoded [String] of library IDs hidden from the home screen.
    @AppStorage("plinx.homeHiddenLibraryIds") private var hiddenIdsJson = "[]"
    /// JSON-encoded [String] of library IDs in preferred display order.
    @AppStorage("plinx.homeLibraryOrder") private var orderJson = "[]"

    /// Live in-memory ordered list of libraries; initialised from stored prefs.
    @State private var orderedLibraries: [Library] = []

    // MARK: - Computed helpers

    private var hiddenIds: Set<String> {
        Set(decodeStringArray(hiddenIdsJson))
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                ForEach(orderedLibraries) { library in
                    HomeLibraryRow(
                        library: library,
                        isEnabled: !hiddenIds.contains(library.id),
                        onToggle: { enabled in
                            toggle(library: library, enabled: enabled)
                        }
                    )
                }
                .onMove { indices, newOffset in
                    orderedLibraries.move(fromOffsets: indices, toOffset: newOffset)
                    persistOrder()
                }
            } header: {
                Label {
                    Text("Recently Added")
                } icon: {
                    Image(systemName: "clock.fill")
                }
            } footer: {
                Text("Choose which libraries appear in the Recently Added rows and drag to set the display order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Home Screen")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .toolbar {
            EditButton()
        }
        .task {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
            buildOrderedList()
        }
        .onChange(of: libraryStore.libraries) { _, _ in
            buildOrderedList()
        }
    }

    // MARK: - Helpers

    /// Merge stored order with actual libraries (handles new libraries added to server).
    private func buildOrderedList() {
        let all = libraryStore.libraries
        let storedOrder = decodeStringArray(orderJson)

        if storedOrder.isEmpty {
            orderedLibraries = all
        } else {
            // Put stored-order libraries first, then append any new ones not in stored order.
            let storedSet = Set(storedOrder)
            let ordered = storedOrder.compactMap { id in all.first { $0.id == id } }
            let extras = all.filter { !storedSet.contains($0.id) }
            orderedLibraries = ordered + extras
        }
    }

    private func toggle(library: Library, enabled: Bool) {
        var ids = Set(decodeStringArray(hiddenIdsJson))
        if enabled {
            ids.remove(library.id)
        } else {
            ids.insert(library.id)
        }
        hiddenIdsJson = encodeStringArray(Array(ids).sorted())
    }

    private func persistOrder() {
        orderJson = encodeStringArray(orderedLibraries.map(\.id))
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
        .tint(.orange)
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
