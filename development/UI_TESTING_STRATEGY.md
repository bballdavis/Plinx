# Plinx UI Testing Strategy

## Approach

Three layers, each with a clear scope:

| Layer | Tool | Scope |
|---|---|---|
| **Logic** | Swift Testing (`@Test`) | Pure functions, models, safety policy, rating parsing |
| **Component rendering** | SnapshotTesting (Point-Free) | Pixel-diff screenshots of PlinxUI components across devices |
| **Critical user paths** | XCUITest | Player launch, tab navigation (run sparingly — slow) |

PlinxCore logic tests run without a simulator. PlinxUI snapshot tests require an iOS simulator but no server.

---

## Package Structure

```
Packages/
  PlinxCore/Tests/PlinxCoreTests/    ← Swift Testing, no UIKit required
  PlinxUI/Tests/PlinxUITests/         ← XCTest + SnapshotTesting (UIKit)
```

### PlinxUI test dependencies (`Package.swift`)

```swift
.package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
```

```swift
.testTarget(
    name: "PlinxUITests",
    dependencies: [
        "PlinxUI",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ]
)
```

---

## What We Test

### PlinxCoreTests — Logic

- `PlinxRating`: parsing from raw strings, ordering, `isTVRating`, `isMovieRating`
- `SafetyInterceptor`: allow/block by label, rating ceiling, unrated passthrough
- `MathGate`: challenge generation, answer validation
- `SafetyPolicy`: movie vs TV split ratings

### PlinxUITests — Modular Structure

Tests are organized into three subdirectories:

```
Tests/PlinxUITests/
├── Fixtures/
│   └── TestFixtures.swift              ← Realistic simulation data + SimulatedSectionRow
├── Logic/
│   └── ContentTypeLayout_LogicTests.swift  ← Swift Testing, no UIKit
├── Snapshots/
│   ├── MovieCard_SnapshotTests.swift   ← Portrait cards, movie type
│   ├── TVCard_SnapshotTests.swift      ← Portrait cards, TV show + episode types
│   ├── ClipCard_SnapshotTests.swift    ← LANDSCAPE cards, clip/YouTube type ★
│   ├── ContinueWatching_SnapshotTests.swift ← Landscape + progress bars
│   └── SectionRow_SnapshotTests.swift  ← Full hub row layout per section
├── PlinxUITests.swift                  ← Legacy theme + component logic tests
└── SnapshotHarnessTests.swift          ← Legacy baseline harness tests
```

#### Fixtures — Simulation Data

`TestFixtures.swift` provides realistic content fixtures without network calls:

| Factory | Content type | Aspect ratio | Card width |
|---|---|---|---|
| `ContentTypeFixtures.movieCards` | Movie (portrait) | 2:3 | 110pt |
| `ContentTypeFixtures.tvShowCards` | TV Show (portrait) | 2:3 | 110pt |
| `ContentTypeFixtures.episodeCards` | Episode + progress | 2:3 | 110pt |
| `ContentTypeFixtures.clipCards` | Clip / YouTube (**landscape**) | **16:9** | **200pt** |
| `ContentTypeFixtures.mixedMoviesAndTV` | Interleaved movie+TV | 2:3 | 110pt |

`SimulatedSectionRow` renders an identical hub-row layout to `PlinxHomeView.hubRow(_:layout:)` — a bold section title above a horizontal strip of fixed-width cards.

#### Logic Tests (`ContentTypeLayout_LogicTests.swift`)

Run without a simulator (`swift test`). Verifies:

- `CGFloat.portraitCard` (2:3) < 1.0 — portrait is taller than wide
- `CGFloat.landscapeCard` (16:9) > 1.0 — landscape is wider than tall
- Clip-type items always get `.landscapeCard` ratio; movies/TV always get `.portraitCard`
- `SimulatedSectionRow` card widths: portrait = 110pt, landscape = 200pt
- Progress bar logic: nil hides bar; 0.0 hides bar; > 1.0 is accepted (view clamps)

#### Snapshot Tests — Content Type Coverage

Each component file is rendered via `UIHostingController` and snapshotted at three device configs:

| Config | Device |
|---|---|
| `.iPhoneSe` | Compact width (320pt), catches text truncation |
| `.iPhoneX` | Standard iPhone (375pt) |
| `.iPadPro12_9` | Regular width (1024pt), catches iPad layout breaks |

**MovieCard_SnapshotTests** — portrait ratio, title + year label, placeholder, long-title truncation

**TVCard_SnapshotTests** — portrait ratio, season-count subtitle, S•E episode label, progress variants (45%, 90%, >100% clamp, 0%)

**ClipCard_SnapshotTests** ★ — **landscape 16:9** ratio at 200pt width, portrait-vs-landscape geometry comparison, labels + progress in landscape orientation

**ContinueWatching_SnapshotTests** — landscape cards with progress at 45/67/90/100/>100/nil, full hub row

**SectionRow_SnapshotTests** — movies+TV portrait row, clip/YouTube landscape row, portrait-vs-landscape side-by-side comparison, all three section titles, iPad card-width invariance

Snapshot baselines live in `Tests/PlinxUITests/__Snapshots__/` and are committed to source control.

### First run — recording baselines

Set `isRecording = true` in the relevant `setUp()` method, run once on iPhone 16 simulator, commit the generated images, set back to `false`.

```bash
xcodebuild test \
  -scheme PlinxUI \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  | xcbeautify
```

### Ongoing — catching regressions

Any layout change that shifts pixels fails the snapshot and produces a diff image in the test result bundle. Review the diff; if intentional (e.g., you fixed a label that was truncating), re-record by setting `isRecording = true` in that file only.

---

## Cross-Device Coverage

Every multi-device snapshot test runs all three configs in one pass using the shared device matrix:

```swift
private static let deviceMatrix: [(name: String, config: ViewImageConfig)] = [
    ("iphoneSE",  .iPhoneSe),
    ("iphone",    .iPhoneX),
    ("iPadPro13", .iPadPro12_9),
]

for device in Self.deviceMatrix {
    assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
}
```

This catches the class of bugs where a component renders correctly on iPhone but collapses/overflows on iPad.

## Key Regression Guards

| Test | What it catches |
|---|---|
| `ClipCard_SnapshotTests.test_clipCard_landscapeRatio_acrossDevices` | Clip/YouTube cards accidentally rendered as portrait |
| `ClipCard_SnapshotTests.test_portraitVsLandscape_geometryComparison_iphone` | Ratio swap between content types |
| `SectionRow_SnapshotTests.test_otherVideosSection_landscapeCards_acrossDevices` | "Other Videos" section using wrong card layout |
| `SectionRow_SnapshotTests.test_portraitVsLandscapeRow_comparison_iphone` | Both section layouts in the same snapshot |
| `ContentTypeLayout_LogicTests.clipFixturesMatchLandscapeLayout` | Fixture data integrity before snapshot runs |
| `ContentTypeLayout_LogicTests.landscapeRatioIsGreaterThanOne` | 16:9 constant correctness |

---

## What Is NOT Tested Here

- **Network / server responses** — mocked at the `PlexAPIContext` boundary
- **Video playback** — MPVKit internal; covered by Strimr's own tests
- **Full app navigation flows** — XCUITest target in PlinxApp (future work)
- **Localization completeness** — validated by `xcodebuild -exportLocalizations` in CI

---

## CI Script

`scripts/ui_tests.sh` — runs both packages across iPhone and iPad:

```bash
#!/bin/bash
set -euo pipefail
for DEST in \
  "platform=iOS Simulator,name=iPhone 15" \
  "platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)"; do
  xcodebuild test \
    -scheme PlinxUI \
    -destination "$DEST" \
    -resultBundlePath "TestResults/$(echo "$DEST" | tr ', ' '__').xcresult" \
    | xcbeautify
done
```
