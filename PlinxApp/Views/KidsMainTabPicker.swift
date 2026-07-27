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
    var focusedTab: FocusState<MainCoordinator.Tab?>.Binding? = nil
    var onAction: (TabItem.Action) -> Void = { _ in }
    var placement: Placement = .floating

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var selectionAnimation
    @AppStorage(PlinxAnimationPreference.playfulAnimationsStorageKey)
    private var playfulAnimationsEnabled = PlinxAnimationPreference.defaultPlayfulAnimationsEnabled
    @State private var playfulSelectionTrigger = 0
    @State private var playfulTiltDirection: Double = 1

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
        if isHeader { return 108 }
        return 154
        #else
        isRegular ? 96 : 110
        #endif
    }
    private var buttonHeight: CGFloat    {
        #if os(tvOS)
        if isInline { return 46 }
        if isHeader { return 52 }
        return 94
        #else
        isRegular ? 64 : 72
        #endif
    }
    private var iconPointSize: CGFloat   {
        #if os(tvOS)
        if isInline { return 18 }
        if isHeader { return 22 }
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
        if isHeader { return 16 }
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
        .onChange(of: selectedTab) { _, _ in
            guard playfulAnimationsEnabled else { return }
            playfulSelectionTrigger &+= 1
            playfulTiltDirection = Bool.random() ? 1 : -1
        }

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
                selectedTab = tab
            }
        } label: {
            TabButtonContent(
                item: item,
                selectedTab: selectedTab,
                playfulAnimationsEnabled: playfulAnimationsEnabled,
                playfulSelectionTrigger: playfulSelectionTrigger,
                playfulTiltDirection: playfulTiltDirection,
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
            playfulAnimationsEnabled
                ? .interpolatingSpring(stiffness: 170, damping: 10)
                : .interpolatingSpring(stiffness: 280, damping: 20),
            value: selectedTab
        )
        .accessibilityIdentifier("main.tab.\(item.id)")

        if let tab = item.tab, let focusedTab {
            button.focused(focusedTab, equals: tab)
        } else {
            button
        }
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

        /// The default main tabs for the Plinx app.
        static func mainTabs(
            includeDownloads: Bool = false,
            showSearchInMainNavigation: Bool = PlinxNavigationPreference.defaultShowSearchInMainNavigation,
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
    let playfulAnimationsEnabled: Bool
    let playfulSelectionTrigger: Int
    let playfulTiltDirection: Double
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
        item.tab.map { selectedTab == $0 } ?? false
    }

    private var isEmphasized: Bool {
        isSelected || isFocused
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: item.iconName)
                .font(.system(size: iconPointSize, weight: .semibold))
                .symbolEffect(
                    .bounce.byLayer,
                    value: playfulAnimationsEnabled && isSelected ? playfulSelectionTrigger : 0
                )
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(isSelected && playfulAnimationsEnabled ? -6 * playfulTiltDirection : 0))

            Text(item.title)
                .font(labelFont.bold())
                .lineLimit(1)
                .minimumScaleFactor(usesCompactDistribution ? 0.68 : 0.85)
                .scaleEffect(isEmphasized && playfulAnimationsEnabled && !isHeader ? 1.05 : 1.0)
        }
            .foregroundStyle(foregroundColor)
        .frame(
            minWidth: usesCompactDistribution ? nil : buttonMinWidth,
            maxWidth: usesCompactDistribution ? .infinity : nil,
            minHeight: buttonHeight
        )
        .background(background)
        .overlay(border)
        .scaleEffect(isEmphasized ? tabScale : 1.0)
        .offset(y: isSelected ? (playfulAnimationsEnabled ? 0 : 1) : 0)
        .rotationEffect(.degrees(isSelected && playfulAnimationsEnabled ? 2.5 * playfulTiltDirection : 0))
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            if isSelected {
                if !isInline {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(playfulAnimationsEnabled ? (isHeader ? 0.26 : 0.22) : (isHeader ? 0.2 : 0.16)))
                        .matchedGeometryEffect(id: "selectedTabBackground", in: selectionAnimation)
                }
            }
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                isEmphasized ? Color.accentColor.opacity(isFocused ? 0.95 : 0.7) : Color.clear,
                lineWidth: isFocused ? (isInline ? 2 : 3) : (isSelected && isInline ? 1.5 : 1)
            )
    }

    private var tabScale: CGFloat {
        #if os(tvOS)
        if isInline { return isFocused ? 1.06 : (isSelected ? 1.03 : 1.0) }
        if isHeader { return isFocused ? 1.09 : (isSelected ? 1.05 : 1.0) }
        return isFocused ? 1.16 : (isSelected ? 1.08 : 1.0)
        #else
        isSelected ? (playfulAnimationsEnabled ? 1.14 : 1.03) : 1.0
        #endif
    }

    private var iconScale: CGFloat {
        if !isEmphasized {
            return 1.0
        }
        if isHeader {
            return playfulAnimationsEnabled ? 1.12 : 1.06
        }
        return playfulAnimationsEnabled ? 1.18 : 1.08
    }

    private var foregroundColor: Color {
        if isSelected {
            return .accentColor
        }
        if isFocused {
            return .white
        }
        return .white.opacity(0.72)
    }

    private var shadowColor: Color {
        guard isEmphasized else { return .clear }
        return Color.accentColor.opacity(isFocused ? 0.7 : 0.25)
    }

    private var shadowRadius: CGFloat {
        #if os(tvOS)
        if isInline { return isFocused ? 16 : (isSelected ? 8 : 0) }
        if isHeader { return isFocused ? 18 : (isSelected ? 10 : 0) }
        return isFocused ? 30 : (isSelected ? 18 : 0)
        #else
        isSelected && playfulAnimationsEnabled ? 24 : 0
        #endif
    }

    private var shadowYOffset: CGFloat {
        #if os(tvOS)
        if isInline || isHeader { return 0 }
        return isFocused ? 0 : (isSelected ? 8 : 0)
        #else
        isSelected && playfulAnimationsEnabled ? 11 : 0
        #endif
    }
}
