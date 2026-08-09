import Combine
import Foundation

/// Every focusable destination in the persistent Apple TV shell.
///
/// Settings is deliberately represented as a real target rather than a tab
/// with a nil coordinator destination, which makes focus restoration
/// deterministic before and after the parental gate.
enum PlinxTVShellFocusTarget: Hashable {
    case tab(MainCoordinator.Tab)
    case settings
}

/// Coarse content ownership used when the shell hands focus back to the
/// currently visible screen.
enum PlinxTVContentRegion: Hashable {
    case home
    case search
    case library
    case libraryDetail
    case detail
    case settings
    case other
}

struct PlinxTVFocusRestoration: Equatable {
    let contentRegion: PlinxTVContentRegion
    let shellTarget: PlinxTVShellFocusTarget?
}

/// Owns the small amount of focus state shared across the persistent tvOS
/// shell. Individual screens continue to own their concrete card/row focus.
@MainActor
final class PlinxTVFocusCoordinator: ObservableObject {
    @Published private(set) var activeContentRegion: PlinxTVContentRegion = .home
    @Published private(set) var contentFocusRequest = 0

    private(set) var lastShellTargetByTab: [MainCoordinator.Tab: PlinxTVShellFocusTarget] = [:]
    private var lastContentTargetByRegion: [PlinxTVContentRegion: AnyHashable] = [:]
    private var modalRestorationStack: [PlinxTVFocusRestoration] = []

    func activate(_ region: PlinxTVContentRegion) {
        activeContentRegion = region
    }

    func requestContentFocus() {
        contentFocusRequest &+= 1
    }

    func rememberShellTarget(_ target: PlinxTVShellFocusTarget, for tab: MainCoordinator.Tab) {
        lastShellTargetByTab[tab] = target
    }

    func rememberContentTarget<ID: Hashable>(_ target: ID, in region: PlinxTVContentRegion) {
        lastContentTargetByRegion[region] = AnyHashable(target)
    }

    func rememberedContentTarget<ID: Hashable>(
        in region: PlinxTVContentRegion,
        availableIDs: [ID]
    ) -> ID? {
        guard let remembered = lastContentTargetByRegion[region]?.base as? ID,
              availableIDs.contains(remembered) else {
            return nil
        }
        return remembered
    }

    func beginModal(from region: PlinxTVContentRegion, shellTarget: PlinxTVShellFocusTarget?) {
        modalRestorationStack.append(
            PlinxTVFocusRestoration(contentRegion: region, shellTarget: shellTarget)
        )
    }

    func endModal() -> PlinxTVFocusRestoration? {
        modalRestorationStack.popLast()
    }

    func preferredShellTarget(
        activeTab: MainCoordinator.Tab,
        showsSettings: Bool,
        visibleTabs: [KidsMainTabPicker.TabItem]
    ) -> PlinxTVShellFocusTarget? {
        if showsSettings,
           visibleTabs.contains(where: { $0.action == .settings }) {
            return .settings
        }

        if let remembered = lastShellTargetByTab[activeTab],
           Self.isVisible(remembered, in: visibleTabs) {
            return remembered
        }

        if visibleTabs.contains(where: { $0.tab == activeTab }) {
            return .tab(activeTab)
        }

        return visibleTabs.compactMap(\.tab).first.map(PlinxTVShellFocusTarget.tab)
    }

    /// Keeps a still-valid content target, otherwise falls back in a stable
    /// order: preferred target, then the first available target.
    nonisolated static func resolvedContentID<ID: Hashable>(
        currentID: ID?,
        availableIDs: [ID],
        preferredID: ID? = nil
    ) -> ID? {
        if let currentID, availableIDs.contains(currentID) {
            return currentID
        }
        if let preferredID, availableIDs.contains(preferredID) {
            return preferredID
        }
        return availableIDs.first
    }

    /// Resolves a removed target to the closest surviving sibling from the
    /// previous ordering before falling back to a preferred or first target.
    nonisolated static func resolvedContentID<ID: Hashable>(
        currentID: ID?,
        previousIDs: [ID],
        availableIDs: [ID],
        preferredID: ID? = nil
    ) -> ID? {
        if let currentID, availableIDs.contains(currentID) {
            return currentID
        }

        if let currentID, let removedIndex = previousIDs.firstIndex(of: currentID) {
            for distance in 1...max(previousIDs.count, 1) {
                let candidates = [removedIndex + distance, removedIndex - distance]
                for index in candidates where previousIDs.indices.contains(index) {
                    let candidate = previousIDs[index]
                    if availableIDs.contains(candidate) {
                        return candidate
                    }
                }
            }
        }

        return resolvedContentID(
            currentID: nil,
            availableIDs: availableIDs,
            preferredID: preferredID
        )
    }

    private static func isVisible(
        _ target: PlinxTVShellFocusTarget,
        in tabs: [KidsMainTabPicker.TabItem]
    ) -> Bool {
        switch target {
        case let .tab(tab):
            tabs.contains(where: { $0.tab == tab })
        case .settings:
            tabs.contains(where: { $0.action == .settings })
        }
    }
}
