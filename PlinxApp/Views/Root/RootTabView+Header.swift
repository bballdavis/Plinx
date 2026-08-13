import SwiftUI
import PlinxCore
import PlinxUI

enum QuickActionFocusDirection {
    case up
    case down
}

enum QuickActionFocusOrder {
    static let cancelID = "cancel"

    static func focusIDs(optionIDs: [String]) -> [String] {
        optionIDs + [cancelID]
    }

    static func nextFocusedID(
        current: String?,
        optionIDs: [String],
        direction: QuickActionFocusDirection
    ) -> String? {
        let ids = focusIDs(optionIDs: optionIDs)
        guard !ids.isEmpty else { return nil }
        guard let current, let currentIndex = ids.firstIndex(of: current) else {
            return ids.first
        }

        switch direction {
        case .up:
            return ids[(currentIndex - 1 + ids.count) % ids.count]
        case .down:
            return ids[(currentIndex + 1) % ids.count]
        }
    }
}

enum HeaderFocusOrder {
    static func returnTarget(
        currentTab: MainCoordinator.Tab,
        visibleTabs: [KidsMainTabPicker.TabItem]
    ) -> MainCoordinator.Tab? {
        let tabs = visibleTabs.compactMap(\.tab)
        if tabs.contains(currentTab) {
            return currentTab
        }
        return tabs.first
    }
}

enum RootTabSelectionPolicy {
    struct Decision: Equatable {
        let destination: MainCoordinator.Tab
        let closesSettings: Bool
        let resetsNavigationStack: Bool
    }

    static func decision(
        isSettingsPresented: Bool,
        currentTab: MainCoordinator.Tab,
        selectedTab: MainCoordinator.Tab
    ) -> Decision {
        Decision(
            destination: selectedTab,
            closesSettings: isSettingsPresented,
            resetsNavigationStack: !isSettingsPresented && currentTab == selectedTab
        )
    }
}

#if os(tvOS)
enum PlinxTVShellLeadingIdentity: Equatable {
    case brand
    case title(String)

    static func resolve(
        showsSettings: Bool,
        activeTab: MainCoordinator.Tab,
        libraryTitle: String?
    ) -> Self {
        if showsSettings {
            return .title("tabs.settings".plinxLocalized)
        }

        switch activeTab {
        case .home:
            return .brand
        case .library, .libraryDetail:
            return .title(libraryTitle ?? "tabs.library".plinxLocalized)
        case .search:
            return .title("tabs.search".plinxLocalized)
        case .more:
            return .title("tabs.downloads".plinxLocalized)
        case .seerrDiscover:
            return .title("youtarr.explore.title".plinxLocalized)
        }
    }
}

struct PlinxTVShellHeader: View {
    let tabs: [KidsMainTabPicker.TabItem]
    let selectedTab: Binding<MainCoordinator.Tab>
    let selectedAction: KidsMainTabPicker.TabItem.Action?
    let leadingIdentity: PlinxTVShellLeadingIdentity
    let focusedTarget: FocusState<PlinxTVShellFocusTarget?>.Binding
    let onSelect: (MainCoordinator.Tab) -> Void
    let onAction: (KidsMainTabPicker.TabItem.Action) -> Void
    let onMoveDown: () -> Void
    var appearance: KidsMainTabPicker.SurfaceAppearance = .standard

    var body: some View {
        KidsMainTabPicker(
            tabs: tabs,
            selectedTab: selectedTab,
            selectedAction: selectedAction,
            focusedTarget: focusedTarget,
            onSelect: onSelect,
            onAction: onAction,
            onMoveDown: onMoveDown,
            placement: .header,
            surfaceAppearance: appearance
        )
        .overlay(alignment: .leading) {
            leadingIdentityView
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
        .padding(.bottom, 4)
        .focusSection()
    }

    @ViewBuilder
    private var leadingIdentityView: some View {
        switch leadingIdentity {
        case .brand:
            PlinxHomeHeaderLogoView(
                accessibilityIdentifier: "tv.shell.logo",
                maxWidth: PlinxTVShellMetrics.logoMaxWidth,
                logoHeight: PlinxTVShellMetrics.logoHeight
            )
            .frame(maxWidth: 320, alignment: .leading)
            // The hero and rows intentionally reclaim half the tvOS leading
            // safe area. Pull the visible lockup onto that same content guide.
            .padding(.leading, PlinxTVShellMetrics.homeBrandLeadingInset)
            .accessibilityHidden(true)

        case let .title(title):
            Text(title)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(
                    appearance == .onBrightBrandSurface
                        ? PlinxBrand.shell
                        : Color.white.opacity(0.96)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(width: 520, alignment: .leading)
                .padding(.leading, 28)
                .accessibilityIdentifier("tv.shell.context.title")
                .accessibilityValue(
                    appearance == .onBrightBrandSurface
                        ? "darkOnBrandGradient"
                        : "lightOnDarkShell"
                )
                .accessibilityAddTraits(.isHeader)
        }
    }
}
#endif
