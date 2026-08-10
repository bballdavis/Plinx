import SwiftUI
import PlinxUI
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// KidsMainTabPicker.swift — Liquid-Glass bottom navigation bar
// ─────────────────────────────────────────────────────────────────────────────
//
// Replaces the native UITabBar with a floating, kid-friendly Liquid Glass tab
// bar that:
//   • Presents wide tap targets                 (easy for children to hit)
//   • Uses Plinx Liquid Glass surface           (frosted material + specular)
//   • Floats above the safe area                (no background band on iPad)
//   • Triggers the Plinx "Plink" feedback       (haptic + audio from PlinxUI)
//
// Accessibility: each button sets `.accessibilityIdentifier("main.tab.<id>")`
// so UITests can locate them.
// ─────────────────────────────────────────────────────────────────────────────

struct KidsMainTabPicker: View {
    enum Placement {
        case floating
        case header
        case inline
    }

    let tabs: [TabItem]
    @Binding var selectedTab: MainCoordinator.Tab
    var selectedAction: TabItem.Action? = nil
    #if os(tvOS)
    var focusedTarget: FocusState<PlinxTVShellFocusTarget?>.Binding? = nil
    #endif
    var onSelect: ((MainCoordinator.Tab) -> Void)? = nil
    var onAction: (TabItem.Action) -> Void = { _ in }
    var onMoveDown: () -> Void = {}
    var placement: Placement = .floating

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var selectionAnimation
    @AppStorage(PlinxAnimationPreference.playfulAnimationsStorageKey)
    private var playfulAnimationsEnabled = PlinxAnimationPreference.defaultPlayfulAnimationsEnabled

    private var isRegular: Bool { sizeClass == .regular }
    private var usesCompactDistribution: Bool {
        #if os(tvOS)
        false
        #else
        !isRegular && tabs.count >= 4
        #endif
    }
    private var isInline: Bool { placement == .inline }
    private var isHeader: Bool { placement == .header }

    // Size tokens — compact (iPhone) vs regular (iPad)
    private var buttonMinWidth: CGFloat  {
        #if os(tvOS)
        if isInline { return 82 }
        if isHeader { return PlinxTVShellMetrics.buttonMinWidth }
        return 154
        #else
        isRegular ? 96 : 110
        #endif
    }
    private var buttonHeight: CGFloat    {
        #if os(tvOS)
        if isInline { return 46 }
        if isHeader { return PlinxTVShellMetrics.buttonHeight }
        return 94
        #else
        isRegular ? 64 : 72
        #endif
    }
    private var iconPointSize: CGFloat   {
        #if os(tvOS)
        if isInline { return 18 }
        if isHeader { return PlinxTVShellMetrics.iconPointSize }
        return 30
        #else
        isRegular ? 22 : (usesCompactDistribution ? 22 : 26)
        #endif
    }
    private var labelFont: Font          {
        #if os(tvOS)
        if isInline { return .caption }
        if isHeader { return .footnote }
        return .headline
        #else
        isRegular ? .caption : (usesCompactDistribution ? .caption2 : .subheadline)
        #endif
    }
    private var cornerRadius: CGFloat    {
        #if os(tvOS)
        if isInline { return 12 }
        if isHeader { return PlinxTVShellMetrics.cornerRadius }
        return 20
        #else
        isRegular ? 14 : 16
        #endif
    }
    private var hSpacing: CGFloat        {
        #if os(tvOS)
        if isInline { return 8 }
        if isHeader { return 12 }
        return 18
        #else
        isRegular ? 8 : (usesCompactDistribution ? 6 : 12)
        #endif
    }
    private var contentHorizontalPadding: CGFloat {
        #if os(tvOS)
        if isInline { return 0 }
        if isHeader { return 24 }
        return 28
        #else
        isRegular ? 20 : (usesCompactDistribution ? 10 : 16)
        #endif
    }
    private var containerHorizontalPadding: CGFloat {
        #if os(tvOS)
        if isInline { return 0 }
        if isHeader { return 18 }
        return 56
        #else
        isRegular ? 40 : (usesCompactDistribution ? 12 : 20)
        #endif
    }

    // MARK: - Body

    var body: some View {
        let row = HStack(spacing: hSpacing) {
            ForEach(tabs) { tab in
                tabButton(tab)
                    .frame(maxWidth: usesCompactDistribution ? .infinity : nil)
            }
        }
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.vertical, isInline ? 0 : (isHeader ? 5 : (playfulAnimationsEnabled ? (isRegular ? 12 : 10) : 10)))

        if isInline {
            row
        } else {
            row
                .liquidGlassBackground()
                .frame(maxWidth: isHeader ? .infinity : nil, alignment: .center)
                .padding(.horizontal, containerHorizontalPadding)
                .padding(.bottom, isHeader ? 0 : 1)
        }
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(_ item: TabItem) -> some View {
        let button = Button {
            if let action = item.action {
                onAction(action)
            } else if let tab = item.tab {
                if let onSelect {
                    onSelect(tab)
                } else {
                    selectedTab = tab
                }
            }
        } label: {
            TabButtonContent(
                item: item,
                selectedTab: selectedTab,
                selectedAction: selectedAction,
                usesCompactDistribution: usesCompactDistribution,
                buttonMinWidth: buttonMinWidth,
                buttonHeight: buttonHeight,
                iconPointSize: iconPointSize,
                labelFont: labelFont,
                cornerRadius: cornerRadius,
                selectionAnimation: selectionAnimation,
                placement: placement
            )
        }
        .buttonStyle(PlinkButtonStyle())
        .animation(
            .easeOut(duration: 0.2),
            value: selectedTab
        )
        .accessibilityIdentifier("main.tab.\(item.id)")

        #if os(tvOS)
        let focusableButton = button
            .focusEffectDisabled()
            .onMoveCommand { direction in
                guard isHeader, direction == .down else { return }
                onMoveDown()
            }

        if let focusedTarget {
            focusableButton.focused(focusedTarget, equals: item.shellFocusTarget)
        } else {
            focusableButton
        }
        #else
        button
        #endif
    }
}

// MARK: - TabItem

extension KidsMainTabPicker {
    struct TabItem: Identifiable {
        enum Action: Equatable {
            case settings
        }

        let id: String
        let tab: MainCoordinator.Tab?
        let action: Action?
        let iconName: String
        let title: LocalizedStringResource

        #if os(tvOS)
        var shellFocusTarget: PlinxTVShellFocusTarget {
            if let tab { return .tab(tab) }
            return .settings
        }

        func isSelected(
            selectedTab: MainCoordinator.Tab,
            selectedAction: Action?
        ) -> Bool {
            if let action {
                return selectedAction == action
            }
            guard selectedAction == nil, let tab else { return false }
            return selectedTab == tab
        }
        #endif

        /// The default main tabs for the Plinx app.
        static func mainTabs(
            includeDownloads: Bool = false,
            showSearchInMainNavigation: Bool = PlinxNavigationPreference.defaultShowSearchInMainNavigation,
            includeExplore: Bool = false,
            includeSettings: Bool = false
        ) -> [TabItem] {
            var tabs: [TabItem] = [
                TabItem(
                    id: "home",
                    tab: .home,
                    action: nil,
                    iconName: "house.fill",
                    title: LocalizedStringResource("tabs.home", table: "Plinx")
                ),
                TabItem(
                    id: "library",
                    tab: .library,
                    action: nil,
                    iconName: "books.vertical.fill",
                    title: LocalizedStringResource("tabs.library", table: "Plinx")
                ),
            ]

            if includeExplore {
                tabs.append(
                    TabItem(
                        id: "explore",
                        tab: .seerrDiscover,
                        action: nil,
                        iconName: "sparkles",
                        title: LocalizedStringResource(
                            "youtarr.explore.title",
                            table: "Plinx"
                        )
                    )
                )
            }

            if showSearchInMainNavigation {
                tabs.append(
                    TabItem(
                        id: "search",
                        tab: .search,
                        action: nil,
                        iconName: "magnifyingglass",
                        title: LocalizedStringResource("tabs.search", table: "Plinx")
                    )
                )
            }

            if includeDownloads {
                tabs.append(
                    TabItem(
                        id: "downloads",
                        tab: .more,
                        action: nil,
                        iconName: "arrow.down.circle.fill",
                        title: LocalizedStringResource("tabs.downloads", table: "Plinx")
                    )
                )
            }

            if includeSettings {
                tabs.append(
                    TabItem(
                        id: "settings",
                        tab: nil,
                        action: .settings,
                        iconName: "gearshape.fill",
                        title: LocalizedStringResource("tabs.settings", table: "Plinx")
                    )
                )
            }

            return tabs
        }
    }
}

private struct TabButtonContent: View {
    let item: KidsMainTabPicker.TabItem
    let selectedTab: MainCoordinator.Tab
    let selectedAction: KidsMainTabPicker.TabItem.Action?
    let usesCompactDistribution: Bool
    let buttonMinWidth: CGFloat
    let buttonHeight: CGFloat
    let iconPointSize: CGFloat
    let labelFont: Font
    let cornerRadius: CGFloat
    let selectionAnimation: Namespace.ID
    let placement: KidsMainTabPicker.Placement

    @Environment(\.isFocused) private var isFocused

    private var isInline: Bool { placement == .inline }
    private var isHeader: Bool { placement == .header }

    private var isSelected: Bool {
        #if os(tvOS)
        item.isSelected(selectedTab: selectedTab, selectedAction: selectedAction)
        #else
        item.tab.map { selectedTab == $0 } ?? false
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: item.iconName)
                .font(.system(size: iconPointSize, weight: .semibold))
                .scaleEffect(isFocused ? 1.06 : 1)

            Text(item.title)
                .font(labelFont.bold())
                .lineLimit(1)
                .minimumScaleFactor(usesCompactDistribution ? 0.68 : 0.85)
        }
        .foregroundStyle(foregroundColor)
        .frame(
            minWidth: usesCompactDistribution ? nil : buttonMinWidth,
            maxWidth: usesCompactDistribution ? .infinity : nil,
            minHeight: buttonHeight
        )
        .background(background)
        .plinxFocusSurface(
            isSelected: isSelected,
            isFocused: isFocused,
            style: PlinxFocusSurfaceStyle(cornerRadius: cornerRadius)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            if isSelected {
                if !isInline {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(isHeader ? 0.20 : 0.16))
                        .matchedGeometryEffect(id: "selectedTabBackground", in: selectionAnimation)
                }
            }
        }
    }

    private var foregroundColor: Color {
        if isFocused {
            return .white
        }
        if isSelected {
            return .accentColor
        }
        return .white.opacity(0.72)
    }
}

#if os(tvOS)
enum PlinxTVShellMetrics {
    static let buttonMinWidth: CGFloat = 108
    static let buttonHeight: CGFloat = 52
    static let iconPointSize: CGFloat = 22
    static let cornerRadius: CGFloat = 16
    static let logoMaxWidth: CGFloat = 220
    static let logoHeight: CGFloat = 52
    static let contentClearance: CGFloat = 76
}
#endif
