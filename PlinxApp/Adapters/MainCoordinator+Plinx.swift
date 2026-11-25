import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Small Plinx conveniences on absorbed navigation and model types.
// ─────────────────────────────────────────────────────────────────────────────

extension MainCoordinator {
    /// Pops a tab's navigation stack to its root.
    ///
    /// Plinx presents a library detail inside the Library tab's stack, so a
    /// library-detail identity resolves to that same root, and reselecting the
    /// persistent Library destination always performs one predictable pop.
    func resetToRoot(for tab: Tab) {
        let rootTab: Tab
        if case .libraryDetail = tab {
            rootTab = .library
        } else {
            rootTab = tab
        }

        let path = pathBinding(for: rootTab)
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue = NavigationPath()
    }

    /// Pops every Plinx tab to its root, e.g. after the content policy changed
    /// and a pushed screen may show an item that is no longer allowed.
    func resetAllToRoot() {
        for tab in [Tab.home, .search, .library, .more, .seerrDiscover] {
            resetToRoot(for: tab)
        }
    }
}

extension Hub {
    /// Synthetic, non-drill-down hub used by grouped home rows and fixtures.
    init(id: String, title: String, items: [MediaDisplayItem]) {
        self.init(
            id: id,
            key: "",
            hubKey: nil,
            title: title,
            size: items.count,
            more: false,
            items: items
        )
    }
}
