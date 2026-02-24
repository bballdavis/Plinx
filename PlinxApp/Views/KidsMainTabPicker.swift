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
        .padding(.vertical, 10)
        .liquidGlassBackground()
        .padding(.horizontal, isRegular ? 40 : 20)
        .padding(.bottom, 4)
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
                Text(item.title)
                    .font(labelFont.bold())
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.7))
            .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlinkButtonStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
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
        static func mainTabs() -> [TabItem] {
            [
                TabItem(
                    id: "home",
                    tab: .home,
                    iconName: "house.fill",
                    title: LocalizedStringResource("tabs.home", table: "Plinx")
                ),
                TabItem(
                    id: "search",
                    tab: .search,
                    iconName: "magnifyingglass",
                    title: LocalizedStringResource("tabs.search", table: "Plinx")
                ),
                TabItem(
                    id: "library",
                    tab: .library,
                    iconName: "square.grid.2x2.fill",
                    title: LocalizedStringResource("tabs.library", table: "Plinx")
                ),
            ]
        }
    }
}
