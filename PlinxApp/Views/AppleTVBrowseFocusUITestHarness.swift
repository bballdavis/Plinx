#if os(tvOS)
import SwiftUI
import PlinxUI

/// Network-free surface for exercising the production tvOS header picker and
/// browse focus contract with real Siri Remote events.
struct AppleTVBrowseFocusUITestHarness: View {
    enum Scenario {
        case root(hasContent: Bool)
        case libraryDetail(hasContent: Bool)
        case search
    }

    private enum ContentTarget: Hashable {
        case homeCard(Int)
        case libraryTile(Int)
        case detailFilter
        case detailCard(Int)
        case searchField
    }

    let scenario: Scenario
    var reduceMotion = false

    @State private var selectedTab: MainCoordinator.Tab = .home
    @StateObject private var focusCoordinator = PlinxTVFocusCoordinator()
    @State private var contentFocusGeneration = 0
    @State private var searchQuery = ""
    @State private var shellFocusHistory: [String] = []
    @FocusState private var focusedShellTarget: PlinxTVShellFocusTarget?
    @FocusState private var focusedContent: ContentTarget?

    private var hasContent: Bool {
        switch scenario {
        case let .root(hasContent), let .libraryDetail(hasContent):
            hasContent
        case .search:
            true
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 42) {
                Color.clear
                    .frame(height: PlinxTVShellMetrics.contentClearance)
                    .accessibilityHidden(true)

                switch scenario {
                case .root:
                    rootContent
                case .libraryDetail:
                    libraryDetailContent
                case .search:
                    searchContent
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 70)
            .padding(.bottom, 70)

            PlinxTVShellHeader(
                tabs: fixtureTabs,
                selectedTab: $selectedTab,
                selectedAction: nil,
                leadingIdentity: shellLeadingIdentity,
                focusedTarget: $focusedShellTarget,
                onSelect: { destination in
                    focusCoordinator.activate(contentRegion(for: destination))
                    focusedShellTarget = .tab(destination)
                    selectedTab = destination
                    focusedContent = nil
                },
                onAction: { _ in },
                onMoveDown: moveDownFromHeader
            )

            Text(shellFocusHistory.joined(separator: ","))
                .font(.system(size: 1))
                .opacity(0.001)
                .accessibilityIdentifier("focus.fixture.shellHistory")
                .accessibilityValue(shellFocusHistory.joined(separator: ","))
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            let destination = scenario.initialTab
            selectedTab = destination
            focusCoordinator.activate(
                scenario.isLibraryDetail ? .libraryDetail : contentRegion(for: destination)
            )
            Task { @MainActor in
                await Task.yield()
                focusedShellTarget = .tab(destination)
            }
        }
        .onChange(of: selectedTab) { _, destination in
            focusedShellTarget = focusCoordinator.shellTarget(
                activeTab: destination,
                showsSettings: false,
                visibleTabs: fixtureTabs
            )
        }
        .onChange(of: focusedShellTarget) { _, target in
            guard let target else { return }
            shellFocusHistory.append(target.fixtureID)
        }
    }

    private var fixtureTabs: [KidsMainTabPicker.TabItem] {
        KidsMainTabPicker.TabItem.mainTabs(
            showSearchInMainNavigation: true,
            includeSettings: true
        )
    }

    private var shellLeadingIdentity: PlinxTVShellLeadingIdentity {
        if scenario.isLibraryDetail {
            return .title("Fixture Library")
        }
        if selectedTab == .home {
            return .brand
        }
        return .title(selectedTab.fixtureID.capitalized)
    }

    @ViewBuilder
    private var rootContent: some View {
        if hasContent {
            if selectedTab == .library {
                HStack(spacing: 28) {
                    fixtureButton(
                        "Library One",
                        identifier: "library.tile.0",
                        isFocused: focusedContent == .libraryTile(0)
                    )
                        .focused($focusedContent, equals: .libraryTile(0))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedShellTarget = .tab(.library)
                        }
                    fixtureButton(
                        "Library Two",
                        identifier: "library.tile.1",
                        isFocused: focusedContent == .libraryTile(1)
                    )
                        .focused($focusedContent, equals: .libraryTile(1))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedShellTarget = .tab(.library)
                        }
                }
            } else {
                HStack(spacing: 28) {
                    fixtureButton(
                        "Home One",
                        identifier: "home.card.fixture.0",
                        isFocused: focusedContent == .homeCard(0)
                    )
                        .focused($focusedContent, equals: .homeCard(0))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedShellTarget = .tab(.home)
                        }
                    fixtureButton(
                        "Home Two",
                        identifier: "home.card.fixture.1",
                        isFocused: focusedContent == .homeCard(1)
                    )
                        .focused($focusedContent, equals: .homeCard(1))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedShellTarget = .tab(.home)
                        }
                }
            }
        } else {
            Text("No focusable content")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("browse.fixture.empty")
        }
    }

    private var libraryDetailContent: some View {
        VStack(spacing: 34) {
            fixtureButton(
                "Recommended",
                identifier: "library.detail.filter.recommended",
                isFocused: focusedContent == .detailFilter
            )
                .focused($focusedContent, equals: .detailFilter)
                .onMoveCommand { direction in
                    switch direction {
                    case .up:
                        focusedShellTarget = .tab(.library)
                    case .down where hasContent:
                        focusedContent = .detailCard(0)
                    default:
                        break
                    }
                }

            if hasContent {
                HStack(spacing: 28) {
                    fixtureButton(
                        "Media One",
                        identifier: "library.detail.card.0",
                        isFocused: focusedContent == .detailCard(0)
                    )
                        .focused($focusedContent, equals: .detailCard(0))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedContent = .detailFilter
                        }
                    fixtureButton(
                        "Media Two",
                        identifier: "library.detail.card.1",
                        isFocused: focusedContent == .detailCard(1)
                    )
                        .focused($focusedContent, equals: .detailCard(1))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedContent = .detailFilter
                        }
                }
            }
        }
    }

    private var searchContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            PlinxTVTextEntry(
                text: $searchQuery,
                placeholder: "Search movies, shows…",
                submitKind: .search
            )
            .focused($focusedContent, equals: .searchField)
            .accessibilityIdentifier("search.fixture.field")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PlinxBrand.surface.opacity(0.98))
        )
        .plinxFocusSurface(
            isSelected: false,
            isFocused: focusedContent == .searchField,
            style: PlinxFocusSurfaceStyle(cornerRadius: 16)
        )
        .focusEffectDisabled()
        .onMoveCommand { direction in
            guard direction == .up else { return }
            contentFocusGeneration &+= 1
            focusedShellTarget = .tab(.search)
        }
    }

    private func fixtureButton(
        _ title: String,
        identifier: String,
        isFocused: Bool
    ) -> some View {
        AppleTVFocusFixtureButton(
            title: title,
            identifier: identifier,
            isFocused: isFocused,
            reduceMotion: reduceMotion
        )
    }

    private func moveDownFromHeader() {
        guard hasContent else { return }
        let target: ContentTarget
        switch scenario {
        case .root:
            if selectedTab == .search {
                target = .searchField
            } else {
                target = selectedTab == .library ? .libraryTile(0) : .homeCard(0)
            }
        case .libraryDetail:
            target = .detailFilter
        case .search:
            target = .searchField
        }

        contentFocusGeneration &+= 1
        let generation = contentFocusGeneration
        focusedContent = nil
        Task { @MainActor in
            await Task.yield()
            guard generation == contentFocusGeneration else { return }
            focusedContent = target
        }
    }

    private func contentRegion(for tab: MainCoordinator.Tab) -> PlinxTVContentRegion {
        switch tab {
        case .home:
            .home
        case .library, .libraryDetail:
            .library
        case .search:
            .search
        case .more, .seerrDiscover:
            .other
        }
    }
}

/// Network-free wrapper that exercises the same nested Menu contract as the
/// production gated Settings destination: one press pops a subpage, and only a
/// press at the Settings root closes the experience.
struct AppleTVSettingsNavigationUITestHarness: View {
    @State private var isSettingsPresented = true
    @State private var selectedTab: MainCoordinator.Tab = .home
    @State private var navigationCoordinator = PlinxSettingsNavigationCoordinator()
    @State private var settingsContentFocusRequest = 0
    @FocusState private var focusedShellTarget: PlinxTVShellFocusTarget?
    @FocusState private var focusedRestoredTab: MainCoordinator.Tab?

    var body: some View {
        ZStack(alignment: .top) {
            if isSettingsPresented {
                NavigationStack {
                    PlinxSettingsView(
                        isUnlocked: true,
                        contentFocusRequest: settingsContentFocusRequest,
                        onRequestShellNavigationFocus: {
                            focusedShellTarget = .settings
                        }
                    )
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear
                            .frame(height: PlinxTVShellMetrics.contentClearance)
                            .accessibilityHidden(true)
                    }
                }
                .environment(\.plinxSettingsNavigationCoordinator, navigationCoordinator)
                .onExitCommand {
                    guard !navigationCoordinator.dismissTopDestination() else { return }
                    isSettingsPresented = false
                }
            } else {
                VStack(spacing: 16) {
                    Text("Settings closed")
                        .accessibilityIdentifier("settings.fixture.closed")
                    Text("Destination")
                        .accessibilityIdentifier("settings.fixture.destination.\(selectedTab.fixtureID)")

                    AppleTVFocusFixtureButton(
                        title: "Restored \(selectedTab.fixtureID.capitalized)",
                        identifier: "settings.fixture.restored.\(selectedTab.fixtureID)",
                        isFocused: focusedRestoredTab == selectedTab
                    )
                    .focused($focusedRestoredTab, equals: selectedTab)
                    .onMoveCommand { direction in
                        guard direction == .up else { return }
                        focusedShellTarget = .tab(selectedTab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PlinxTVShellHeader(
                tabs: KidsMainTabPicker.TabItem.mainTabs(
                    showSearchInMainNavigation: true,
                    includeSettings: true
                ),
                selectedTab: $selectedTab,
                selectedAction: isSettingsPresented ? .settings : nil,
                leadingIdentity: isSettingsPresented
                    ? .title("Settings")
                    : (selectedTab == .home
                        ? .brand
                        : .title(selectedTab.fixtureID.capitalized)),
                focusedTarget: $focusedShellTarget,
                onSelect: exitSettings(to:),
                onAction: { action in
                    guard action == .settings, !isSettingsPresented else { return }
                    isSettingsPresented = true
                },
                onMoveDown: {
                    if isSettingsPresented {
                        settingsContentFocusRequest &+= 1
                    } else {
                        focusedRestoredTab = selectedTab
                    }
                }
            )
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private func exitSettings(to destination: MainCoordinator.Tab) {
        selectedTab = destination
        isSettingsPresented = false
        focusedShellTarget = .tab(destination)
    }
}

private struct AppleTVFocusFixtureButton: View {
    let title: String
    let identifier: String
    let isFocused: Bool
    var reduceMotion = false

    var body: some View {
        Button {} label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.52), Color.black.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(22)
            }
            .frame(width: 360, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .plinxTVCardFocusArtwork(
                isFocused: isFocused,
                cornerRadius: 18,
                focusedScale: reduceMotion ? 1 : 1.08
            )
        }
        .buttonStyle(PlinkButtonStyle())
        .focusEffectDisabled()
        .accessibilityIdentifier(identifier)
    }
}

private extension MainCoordinator.Tab {
    var fixtureID: String {
        switch self {
        case .home: "home"
        case .library, .libraryDetail: "library"
        case .search: "search"
        case .more: "more"
        case .seerrDiscover: "explore"
        }
    }
}

private extension AppleTVBrowseFocusUITestHarness.Scenario {
    var isLibraryDetail: Bool {
        if case .libraryDetail = self { return true }
        return false
    }

    var initialTab: MainCoordinator.Tab {
        switch self {
        case .root:
            .home
        case .libraryDetail:
            .library
        case .search:
            .search
        }
    }
}

private extension PlinxTVShellFocusTarget {
    var fixtureID: String {
        switch self {
        case let .tab(tab):
            tab.fixtureID
        case .settings:
            "settings"
        }
    }
}
#endif
