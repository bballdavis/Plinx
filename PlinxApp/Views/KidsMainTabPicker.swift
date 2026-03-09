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
    let tabs: [TabItem]
    @Binding var selectedTab: MainCoordinator.Tab

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var selectionAnimation
    @AppStorage(PlinxAnimationPreference.playfulAnimationsStorageKey)
    private var playfulAnimationsEnabled = PlinxAnimationPreference.defaultPlayfulAnimationsEnabled
    @State private var playfulSelectionTrigger = 0
    @State private var playfulTiltDirection: Double = 1

    private var isRegular: Bool { sizeClass == .regular }

    // Size tokens — compact (iPhone) vs regular (iPad)
    private var buttonMinWidth: CGFloat  { isRegular ? 96 : 110 }
    private var buttonHeight: CGFloat    { isRegular ? 64 : 72 }
    private var iconPointSize: CGFloat   { isRegular ? 22 : 26 }
    private var labelFont: Font          { isRegular ? .caption : .subheadline }
    private var cornerRadius: CGFloat    { isRegular ? 14 : 16 }
    private var hSpacing: CGFloat        { isRegular ? 8 : 12 }

    // MARK: - Body

    var body: some View {
        HStack(spacing: hSpacing) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, isRegular ? 20 : 16)
        .padding(.vertical, playfulAnimationsEnabled ? (isRegular ? 12 : 10) : 10)
        .liquidGlassBackground()
        .padding(.horizontal, isRegular ? 40 : 20)
        .padding(.bottom, 1)
        .onChange(of: selectedTab) { _, _ in
            guard playfulAnimationsEnabled else { return }
            playfulSelectionTrigger &+= 1
            playfulTiltDirection = Bool.random() ? 1 : -1
        }
        .accessibilityIdentifier("main.tabPicker")
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(_ item: TabItem) -> some View {
        let isSelected = selectedTab == item.tab
        Button {
            selectedTab = item.tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.iconName)
                    .font(.system(size: iconPointSize, weight: .semibold))
                    .symbolEffect(
                        .bounce.byLayer,
                        value: playfulAnimationsEnabled && isSelected ? playfulSelectionTrigger : 0
                    )
                    .scaleEffect(isSelected ? (playfulAnimationsEnabled ? 1.18 : 1.0) : 1.0)
                    .rotationEffect(.degrees(isSelected && playfulAnimationsEnabled ? -6 * playfulTiltDirection : 0))
                Text(item.title)
                    .font(labelFont.bold())
                    .lineLimit(1)
                    .scaleEffect(isSelected && playfulAnimationsEnabled ? 1.05 : 1.0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.7))
            .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(playfulAnimationsEnabled ? 0.3 : 0.18))
                            .matchedGeometryEffect(id: "selectedTabBackground", in: selectionAnimation)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? (playfulAnimationsEnabled ? 1.14 : 1.03) : 1.0)
            .offset(y: isSelected ? (playfulAnimationsEnabled ? 0 : 1) : 0)
            .rotationEffect(.degrees(isSelected && playfulAnimationsEnabled ? 2.5 * playfulTiltDirection : 0))
            .shadow(
                color: isSelected && playfulAnimationsEnabled ? Color.accentColor.opacity(0.25) : .clear,
                radius: isSelected && playfulAnimationsEnabled ? 24 : 0,
                y: isSelected && playfulAnimationsEnabled ? 11 : 0
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlinkButtonStyle())
        .animation(
            playfulAnimationsEnabled
                ? .interpolatingSpring(stiffness: 170, damping: 10)
                : .interpolatingSpring(stiffness: 280, damping: 20),
            value: selectedTab
        )
        .accessibilityIdentifier("main.tab.\(item.id)")
    }
}

// MARK: - TabItem

extension KidsMainTabPicker {
    struct TabItem: Identifiable {
        let id: String
        let tab: MainCoordinator.Tab
        let iconName: String
        let title: LocalizedStringResource

        /// The default main tabs for the Plinx app.
        static func mainTabs(
            includeDownloads: Bool = false,
            showSearchInMainNavigation: Bool = PlinxNavigationPreference.defaultShowSearchInMainNavigation
        ) -> [TabItem] {
            var tabs: [TabItem] = [
                TabItem(
                    id: "home",
                    tab: .home,
                    iconName: "house.fill",
                    title: LocalizedStringResource("tabs.home", table: "Plinx")
                ),
            ]

            if showSearchInMainNavigation {
                tabs.append(
                    TabItem(
                        id: "search",
                        tab: .search,
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
                        iconName: "arrow.down.circle.fill",
                        title: LocalizedStringResource("tabs.downloads", table: "Plinx")
                    )
                )
            }

            tabs.append(contentsOf: [
                TabItem(
                    id: "library",
                    tab: .library,
                    iconName: "books.vertical.fill",
                    title: LocalizedStringResource("tabs.library", table: "Plinx")
                ),
            ])

            return tabs
        }
    }
}
