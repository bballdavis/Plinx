# Testing & Quality Assurance

Plinx testing is run in a strict order so regressions are caught quickly and cheaply before live-server runs.

## Regression Execution Order

1. **Unit tests (fast, deterministic)**
2. **Targeted UI tests on simulator (navigation/layout regressions)**
3. **Live UI tests (real Plex data/render checks)**

## Regression Matrix (Current Priority)

| Area | What to verify | Primary tests |
|---|---|---|
| Home grouping | Movies+TV combined row stays separate from Other Videos; unmatched hubs are not dropped | `HomeLibraryGroupingTests` |
| Other-video letterbox | Other-video thumbnails are landscape while Movies/TV remain portrait | `HomeScreenSectionUITests`, `LiveRenderSmokeUITests` |
| Main navigation row | Only one native tab row (no custom duplicate row) | `LibraryTabUITests.test_mainNavigation_usesSingleNativeTabBar` |
| Library browse spacing | Browse list/grid keeps non-zero rendered items while scrolling/paginating (no phantom blank slots) | `LibraryTabUITests.test_libraryBrowse_continuousItems_noZeroSizedPhantomSlots` |

## Local Commands

### 1) Unit tests

```bash
xcodebuild test \
	-project PlinxApp/Plinx.xcodeproj \
	-scheme Plinx-iOS \
	-destination "platform=iOS Simulator,name=iPad (10th generation)" \
	-only-testing:Plinx-iOS-UnitTests
```

### 2) Targeted UI tests (non-live)

```bash
xcodebuild test \
	-project PlinxApp/Plinx.xcodeproj \
	-scheme Plinx-iOS \
	-destination "platform=iOS Simulator,name=iPad (10th generation)" \
	-only-testing:Plinx-iOS-UITests/LibraryTabUITests
```

### 3) Live UI tests (requires credentials)

```bash
xcodebuild test \
	-project PlinxApp/Plinx.xcodeproj \
	-scheme Plinx-iOS \
	-destination "platform=iOS Simulator,name=iPad (10th generation)" \
	-only-testing:Plinx-iOS-UITests/HomeScreenSectionUITests \
	-only-testing:Plinx-iOS-UITests/LiveRenderSmokeUITests
```

## Live Credentials & Skip Behavior

- Configure `test_creds.yaml` (copy from `test_creds.yaml.example`) with:
	- `PLINX_PLEX_SERVER_URL`
	- `PLINX_PLEX_TOKEN` (or user/password/PIN path)
- Live tests are designed to **skip** when credentials are unavailable rather than fail unrelated PRs.

## Device Targets

- iPhone (default scripts target) for compact tab bar behavior.
- iPad (10th generation) for regular-width navigation and browse-grid regressions.
