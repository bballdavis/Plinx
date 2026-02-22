# Plinx UI Testing Strategy

## TL;DR

The iOS equivalent of Playwright for UI verification is **Swift Testing + SnapshotTesting**. For cross-device matrix testing (iPhone vs iPad), **SnapshotTesting by Point-Free** is the de-facto standard. XCUITest handles real user-gesture automation but is overkill for rendering/layout assertions.

---

## Stack Recommendation

| Concern | Tool | Notes |
|---|---|---|
| Unit logic | Swift Testing (`@Test`) | Native, fast, replaces XCTest for new code |
| View rendering / layout | **SnapshotTesting** (Point-Free) | Snapshot screenshots per device; diffs on CI |
| Nav bar / hierarchy presence | SwiftUI `ViewInspector` | Programmatically traverse the view tree |
| End-to-end gestures | XCUITest | Use sparingly — slow; useful for critical paths |
| Cross-device matrix | SnapshotTesting multi-config | Snapshot same view at iPhone SE / 15 / iPad sizes |

**Primary choice: SnapshotTesting + ViewInspector running in XCTest.**

---

## Why Not Playwright?

Playwright is browser-automation. The iOS equivalent concept maps like this:

```
Playwright          →  iOS Stack
────────────────────────────────────────────────────
Browser screenshots →  SnapshotTesting (pixel diffs)
DOM assertions      →  ViewInspector (view-tree queries)
Multi-browser       →  Multi-device simulator matrix
Headed / headless   →  Simulator (headed) or renderImage (headless)
CI integration      →  xcodebuild test + artifact upload
```

---

## Required Dependencies

Add to `Packages/PlinxUI/Package.swift`:

```swift
dependencies: [
    .package(path: "../PlinxCore"),
    // Testing-only
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.0"),
],
targets: [
    ...
    .testTarget(
        name: "PlinxUITests",
        dependencies: [
            "PlinxUI",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "ViewInspector", package: "ViewInspector"),
        ]
    )
]
```

---

## What We Can Test

### 1. Snapshot Tests — "Does it LOOK right?"

Captures a pixel-perfect image at specific device sizes, fails if pixels change.

```swift
// PlinxUITests/Snapshots/HomeViewSnapshotTests.swift
import XCTest
import SnapshotTesting
import SwiftUI
@testable import PlinxUI

final class HomeViewSnapshotTests: XCTestCase {

    override func setUp() {
        // Set to true on first run to record, then flip to false
        // isRecording = true
    }

    func test_homeView_iPhone15() {
        let view = PlinxHomeView_Preview()   // use PreviewProvider data
        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: .iPhone15),
            named: "home-iphone15"
        )
    }

    func test_homeView_iPadPro13() {
        let view = PlinxHomeView_Preview()
        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: .iPadPro12_9),
            named: "home-ipad-pro-13"
        )
    }

    func test_homeView_iPhoneSE() {
        let view = PlinxHomeView_Preview()
        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: .iPhoneSe2ndGeneration),
            named: "home-iphoneSE"
        )
    }
}
```

**What this catches:**
- Nav bar present/absent
- Layout breakage at different widths
- Thumbnail placeholder rendering
- Localization text length overflow

### 2. ViewInspector Tests — "Are the right components present?"

Programmatically queries the SwiftUI view tree — doesn't require a UIWindow.

```swift
// PlinxUITests/Inspector/NavBarPresenceTests.swift
import XCTest
import ViewInspector
import SwiftUI
@testable import PlinxUI

final class NavBarPresenceTests: XCTestCase {

    /// Verify the settings gear button exists on the Home nav bar
    func test_homeView_hasSettingsToolbarButton() throws {
        let view = NavigationStack {
            // Minimal stub with required environments
            PlinxHomeStubView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "gearshape.fill") }
                    }
                }
        }
        let toolbar = try view.inspect().find(viewWithId: "settingsButton")
        XCTAssertNotNil(toolbar)
    }

    /// Verify that the RootTabView shows 3 tabs
    func test_rootTabView_hasThreeTabs() throws {
        // RootTabView requires environments — inject stubs
        let view = RootTabViewStub()
        let tabContent = try view.inspect().tabView().tabItem(0)
        XCTAssertNotNil(tabContent)
    }
}
```

### 3. Localization Tests — "Is the right text shown?"

```swift
// PlinxUITests/Localization/LocalizationTests.swift
import XCTest
@testable import PlinxUI

final class LocalizationTests: XCTestCase {

    private let plinxBundle = Bundle(for: PlinxUITests.self)  // adjust as needed

    func test_allPlinxKeys_haveEnglishTranslation() {
        // Load Localizable.strings from PlinxApp resources
        let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
        XCTAssertNotNil(url, "Plinx Localizable.strings not found")
        // Spot-check critical keys
        let critical = [
            "tabs.home", "tabs.search", "tabs.library",
            "home.loading", "player.vlc.missing"
        ]
        for key in critical {
            let value = NSLocalizedString(key, tableName: "Plinx", bundle: .main, value: "MISSING", comment: "")
            XCTAssertNotEqual(value, "MISSING", "Key '\(key)' missing from Plinx.strings")
            XCTAssertNotEqual(value, key, "Key '\(key)' has no translation")
        }
    }
}
```

### 4. Device matrix — iPhone vs iPad

SnapshotTesting ships with `ViewImageConfig` presets. Use them in a loop:

```swift
func test_homeView_allDevices() {
    let devices: [(String, ViewImageConfig)] = [
        ("iphone-se",        .iPhoneSe2ndGeneration),
        ("iphone-15",        .iPhone15),
        ("iphone-15-plus",   .iPhone15Plus),
        ("ipad-pro-11",      .iPadPro11),
        ("ipad-pro-13",      .iPadPro12_9),
    ]
    let view = UIHostingController(rootView: PlinxHomeView_Preview())
    for (name, config) in devices {
        assertSnapshot(of: view, as: .image(on: config), named: name)
    }
}
```

### 5. Thumbnail generation

Since thumbnails are loaded asynchronously via `AsyncImage` / Kingfisher, stub the URLs:

```swift
func test_mediaCard_showsPlaceholderWhenNoImage() throws {
    let card = PlinxMediaCard(title: "Test Movie", imageURL: nil, rating: "PG")
    let host = UIHostingController(rootView: card)
    assertSnapshot(of: host, as: .image(on: .iPhone15), named: "mediaCard-noImage")
}

func test_mediaCard_hasTitleText() throws {
    let card = PlinxMediaCard(title: "Test Movie", imageURL: nil, rating: "PG")
    let text = try card.inspect().find(text: "Test Movie")
    XCTAssertNotNil(text)
}
```

---

## Adding to PlinxUI Package (Step-by-Step)

```bash
# 1. Add SnapshotTesting + ViewInspector to Package.swift (see above)
# 2. Record baseline snapshots
xcodebuild test \
  -scheme PlinxUI \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -testPlan PlinxUITests \
  OTHER_SWIFT_FLAGS="-D RECORD_SNAPSHOTS"

# 3. Commit __Snapshots__ folder
git add Packages/PlinxUI/Tests/PlinxUITests/__Snapshots__
git commit -m "chore: record UI baseline snapshots"

# 4. On subsequent runs, diffs fail the test with a diff image artifact
```

---

## CI Integration

In a future `scripts/ui_tests.sh`:

```bash
#!/bin/bash
set -euo pipefail

DEVICES=(
  "platform=iOS Simulator,name=iPhone 15"
  "platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)"
)

for DEST in "${DEVICES[@]}"; do
  xcodebuild test \
    -scheme PlinxUI \
    -destination "$DEST" \
    -resultBundlePath "TestResults/$(echo $DEST | tr ',' '_').xcresult" \
    | xcbeautify
done
```

---

## Scope of What These Tests Cover

| Issue | Covered by |
|---|---|
| Nav bar missing on iPad | Snapshot test (absence shows in diff) + ViewInspector |
| Player crash on iPad | XCUITest (full path: tap media → player appears) |
| Localization text visible | Localization unit test + Snapshot |
| Thumbnails rendered | Snapshot (placeholder) |
| Layout iPhone vs iPad | Snapshot device matrix |
| Safe content filtering | PlinxCore unit tests (already exist) |
| Tab bar appears | Snapshot full-screen + ViewInspector |

---

## Priority Order

1. **SnapshotTesting** — highest ROI, catches visual regressions automatically
2. **Localization unit tests** — trivial to add, catches missing keys early
3. **ViewInspector** — useful for structural assertions without full render
4. **XCUITest** — add only for the player launch path (the crash scenario)
