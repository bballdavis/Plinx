#if os(tvOS)
import SwiftUI

/// Network-free surface for exercising the production tvOS header picker and
/// browse focus contract with real Siri Remote events.
struct AppleTVBrowseFocusUITestHarness: View {
    enum Scenario {
        case root(hasContent: Bool)
        case libraryDetail(hasContent: Bool)
    }

    private enum ContentTarget: Hashable {
        case homeCard(Int)
        case libraryTile(Int)
        case detailFilter
        case detailCard(Int)
    }

    let scenario: Scenario

    @State private var selectedTab: MainCoordinator.Tab = .home
    @FocusState private var focusedHeaderTab: MainCoordinator.Tab?
    @FocusState private var focusedContent: ContentTarget?

    private var hasContent: Bool {
        switch scenario {
        case let .root(hasContent), let .libraryDetail(hasContent):
            hasContent
        }
    }

    var body: some View {
        VStack(spacing: 42) {
            KidsMainTabPicker(
                tabs: KidsMainTabPicker.TabItem.mainTabs(
                    showSearchInMainNavigation: true,
                    includeSettings: true
                ),
                selectedTab: $selectedTab,
                focusedTab: $focusedHeaderTab,
                onMoveDown: moveDownFromHeader,
                placement: .header
            )

            switch scenario {
            case .root:
                rootContent
            case .libraryDetail:
                libraryDetailContent
            }

            Spacer(minLength: 0)
        }
        .padding(70)
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            focusedHeaderTab = scenario.isLibraryDetail ? .library : .home
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if hasContent {
            if selectedTab == .library {
                HStack(spacing: 28) {
                    fixtureButton("Library One", identifier: "library.tile.0")
                        .focused($focusedContent, equals: .libraryTile(0))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedHeaderTab = .home
                        }
                    fixtureButton("Library Two", identifier: "library.tile.1")
                        .focused($focusedContent, equals: .libraryTile(1))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedHeaderTab = .home
                        }
                }
            } else {
                HStack(spacing: 28) {
                    fixtureButton("Home One", identifier: "home.card.fixture.0")
                        .focused($focusedContent, equals: .homeCard(0))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedHeaderTab = .home
                        }
                    fixtureButton("Home Two", identifier: "home.card.fixture.1")
                        .focused($focusedContent, equals: .homeCard(1))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedHeaderTab = .home
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
            fixtureButton("Recommended", identifier: "library.detail.filter.recommended")
                .focused($focusedContent, equals: .detailFilter)
                .onMoveCommand { direction in
                    switch direction {
                    case .up:
                        focusedHeaderTab = .home
                    case .down where hasContent:
                        focusedContent = .detailCard(0)
                    default:
                        break
                    }
                }

            if hasContent {
                HStack(spacing: 28) {
                    fixtureButton("Media One", identifier: "library.detail.card.0")
                        .focused($focusedContent, equals: .detailCard(0))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedContent = .detailFilter
                        }
                    fixtureButton("Media Two", identifier: "library.detail.card.1")
                        .focused($focusedContent, equals: .detailCard(1))
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            focusedContent = .detailFilter
                        }
                }
            }
        }
    }

    private func fixtureButton(_ title: String, identifier: String) -> some View {
        Button {} label: {
            Text(title)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .frame(width: 360, height: 150)
        }
        .accessibilityIdentifier(identifier)
    }

    private func moveDownFromHeader() {
        guard hasContent else { return }
        switch scenario {
        case .root:
            focusedContent = selectedTab == .library ? .libraryTile(0) : .homeCard(0)
        case .libraryDetail:
            focusedContent = .detailFilter
        }
    }
}

private extension AppleTVBrowseFocusUITestHarness.Scenario {
    var isLibraryDetail: Bool {
        if case .libraryDetail = self { return true }
        return false
    }
}
#endif
