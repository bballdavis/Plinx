import XCTest
import PlinxUI
@testable import Plinx

final class AppleTVBrowseFocusRoutingTests: XCTestCase {
    func test_shellUsesBrandOnlyOnHome() {
        XCTAssertEqual(
            PlinxTVShellLeadingIdentity.resolve(
                showsSettings: false,
                activeTab: .home,
                libraryTitle: nil
            ),
            .brand
        )

        XCTAssertEqual(
            PlinxTVShellLeadingIdentity.resolve(
                showsSettings: false,
                activeTab: .library,
                libraryTitle: "YouTube Videos"
            ),
            .title("YouTube Videos")
        )

        guard case .title = PlinxTVShellLeadingIdentity.resolve(
            showsSettings: true,
            activeTab: .home,
            libraryTitle: nil
        ) else {
            return XCTFail("Settings must replace the Home brand with a contextual title")
        }
    }

    func test_settingsActionOwnsSelectionWhileSettingsIsVisible() throws {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(includeSettings: true)
        let home = try XCTUnwrap(tabs.first(where: { $0.id == "home" }))
        let settings = try XCTUnwrap(tabs.first(where: { $0.id == "settings" }))

        XCTAssertFalse(home.isSelected(selectedTab: .home, selectedAction: .settings))
        XCTAssertTrue(settings.isSelected(selectedTab: .home, selectedAction: .settings))
        XCTAssertTrue(home.isSelected(selectedTab: .home, selectedAction: nil))
        XCTAssertFalse(settings.isSelected(selectedTab: .home, selectedAction: nil))
    }

    func test_contentFocusFallback_isNilWhenARegionHasNoFocusableItems() {
        XCTAssertNil(
            PlinxTVFocusCoordinator.resolvedContentID(
                currentID: "removed",
                availableIDs: [String](),
                preferredID: "also-removed"
            )
        )
    }

    func test_settingsToTabDecisionClosesWithoutResettingSavedNavigation() {
        let decision = RootTabSelectionPolicy.decision(
            isSettingsPresented: true,
            currentTab: .home,
            selectedTab: .library
        )

        XCTAssertEqual(decision.destination, .library)
        XCTAssertTrue(decision.closesSettings)
        XCTAssertFalse(decision.resetsNavigationStack)
    }

    func test_settingsFocusStyleUsesStableScaleAndDarkAccentCue() {
        let style = PlinxFocusSurfaceStyle.tvSettings(cornerRadius: 20)

        XCTAssertEqual(style.focusedScale, 1)
        XCTAssertEqual(style.cornerRadius, 20)
        XCTAssertEqual(style.focusedFillOpacity, 0.14)
        XCTAssertEqual(style.resolvedScale(isFocused: true, reduceMotion: false), 1)
    }

    func test_headerReturnTarget_keepsCurrentVisibleTab() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(
            showSearchInMainNavigation: true,
            includeSettings: true
        )

        XCTAssertEqual(
            HeaderFocusOrder.returnTarget(currentTab: .library, visibleTabs: tabs),
            .library
        )
    }

    func test_headerReturnTarget_fallsBackToFirstRealTabWhenHomeIsMissing() {
        let tabs = KidsMainTabPicker.TabItem.mainTabs(showSearchInMainNavigation: true)
            .filter { $0.tab != .home }

        XCTAssertEqual(
            HeaderFocusOrder.returnTarget(currentTab: .home, visibleTabs: tabs),
            .library
        )
    }

    func test_upFromFirstHomeRow_routesToNavigation() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 0, rowCount: 3),
            .navigation
        )
    }

    func test_verticalHomeMovement_targetsFirstCardInAdjacentRow() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 0, rowCount: 3),
            .card(row: 1, item: 0)
        )
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 2, rowCount: 3),
            .card(row: 1, item: 0)
        )
    }

    func test_downFromLastHomeRow_doesNotMoveFocus() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 2, rowCount: 3),
            .unchanged
        )
    }

    func test_homeRouting_handlesSingleRowAndEmptyStates() {
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: 0, rowCount: 1),
            .navigation
        )
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 0, rowCount: 1),
            .unchanged
        )
        XCTAssertEqual(
            HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: 0, rowCount: 0),
            .unchanged
        )
    }

    func test_sharedHeroMetrics_extendBackdropWithoutMovingContentGuide() {
        XCTAssertEqual(TvBrowseHeroMetrics.default.heightRatio, 0.408, accuracy: 0.0001)
        XCTAssertEqual(TvBrowseHeroMetrics.home.heightRatio, 0.408, accuracy: 0.0001)
        XCTAssertEqual(TvBrowseHeroMetrics.backdropHeightRatio, 0.68, accuracy: 0.0001)
        XCTAssertGreaterThan(
            TvBrowseHeroMetrics.backdropHeightRatio,
            TvBrowseHeroMetrics.default.heightRatio
        )
        XCTAssertEqual(
            TvBrowseHeroMetrics.default.backdropFadeStartLocation,
            0.6,
            accuracy: 0.0001
        )
    }

    func test_sharedHeroMetadata_reservesFourLineFootprint() {
        XCTAssertEqual(TvBrowseHeroMetrics.metadataRowHeight, 28)
        XCTAssertEqual(TvBrowseHeroMetrics.summaryHeight, 112)
        XCTAssertEqual(TvBrowseHeroMetrics.summaryLineLimit, 4)
    }

    func test_removedFocusedItem_fallsBackToNearestSibling() {
        XCTAssertEqual(
            PlinxTVFocusCoordinator.resolvedContentID(
                currentID: "b",
                previousIDs: ["a", "b", "c"],
                availableIDs: ["a", "c"]
            ),
            "c"
        )
    }

    func test_recommendationsAddDiscoveryWhenOnlyContinueWatchingExists() {
        let continueWatching = Hub(
            id: "hub.inProgress",
            title: "Continue Watching",
            items: [collection("continue")]
        )

        XCTAssertTrue(
            LibraryRecommendationFallbackPolicy.needsDiscoveryHub([continueWatching])
        )
    }

    func test_recommendationsKeepARealPlexDiscoveryHub() {
        let continueWatching = Hub(
            id: "hub.inProgress",
            title: "Continue Watching",
            items: [collection("continue")]
        )
        let topRated = Hub(
            id: "hub.topRated",
            title: "Top Rated",
            items: [collection("top")]
        )

        XCTAssertFalse(
            LibraryRecommendationFallbackPolicy.needsDiscoveryHub([continueWatching, topRated])
        )
    }

    func test_discoveryCandidatesExcludeExistingItemsAndPreserveOrder() {
        let existing = Hub(
            id: "hub.inProgress",
            title: "Continue Watching",
            items: [collection("existing")]
        )
        let candidates = [
            collection("existing"),
            collection("new-1"),
            collection("new-1"),
            collection("new-2")
        ]

        let result = LibraryRecommendationFallbackPolicy.discoveryItems(
            from: candidates,
            excluding: [existing]
        )

        XCTAssertEqual(result.map(\.id), ["new-1", "new-2"])
    }

    private func collection(_ id: String) -> MediaDisplayItem {
        .collection(
            CollectionMediaItem(
                id: id,
                key: "/library/collections/\(id)/children",
                guid: "plex://collection/\(id)",
                type: .collection,
                title: id,
                summary: nil,
                thumbPath: nil,
                childCount: nil,
                minYear: nil,
                maxYear: nil
            )
        )
    }
}
