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

Set `isRecording = true` in the relevant `setUp()` method, run once on an available simulator (default: iPhone 17), commit the generated images, set back to `false`.

```bash
xcodebuild test \
  -scheme PlinxUI \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
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
- **Localization completeness** — validated by `xcodebuild -exportLocalizations` in CI

## Live UI Smoke (Playwright-style)

Plinx now includes an app-level XCUITest target in `PlinxApp/UITests` for live render checks while connected to a real Plex server.

### Coverage

- `LaunchSmokeUITests.test_appLaunches` — verifies app boot path
- `LiveRenderSmokeUITests.test_liveHomeRendersPrimarySections` — waits for live home content sections
- `LiveRenderSmokeUITests.test_liveOtherVideosThumbnailIsLandscape` — verifies "Other Videos" thumbnail geometry is landscape
- `LiveRenderSmokeUITests.test_liveMovieThumbnailIsPortrait` — verifies Movies/TV thumbnail geometry is portrait
- `LiveRenderSmokeUITests.test_liveLandscapeAndPortraitDiffer` — validates clear ratio divergence across section types

The tests use deterministic accessibility identifiers added in `PlinxHomeView`:

- `home.hub.continueWatching`, `home.hub.moviesAndTV`, `home.hub.otherVideos`
- `home.thumbnail.<section>.<index>`
- `home.card.<section>.<index>`

### Run command

```bash
./scripts/ui_tests.sh --live
```

### Live Plex Credentials (YAML)

To run real-server assertions, create a `test_creds.yaml` file in the project root (copied from `test_creds.yaml.example`):

- `PLINX_PLEX_SERVER_URL`: Your Plex server address
- `PLINX_PLEX_TOKEN`: Your auth token (primary method)

The `scripts/ui_tests.sh --live` command automatically loads this file. If missing, live rendering assertions are skipped while basic launch smoke tests still run.

---

## CI Script

`scripts/ui_tests.sh` supports logic, snapshot, recording, and live smoke modes:

```bash
./scripts/ui_tests.sh --core
./scripts/ui_tests.sh --ui
./scripts/ui_tests.sh --snapshots
./scripts/ui_tests.sh --record
./scripts/ui_tests.sh --live
```
