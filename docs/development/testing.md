# Testing

Use this file as the canonical test index for Plinx.

## Test Layers

Plinx uses four main test layers:

1. Logic tests for pure functions and domain behavior
2. Snapshot tests for reusable UI components
3. App unit tests for app-specific integration behavior
4. UI and live tests for user-path and real-data verification

## Core Commands

### PlinxCore package tests

```bash
swift test --package-path Packages/PlinxCore
```

### PlinxUI package tests

```bash
swift test --package-path Packages/PlinxUI
```

### App unit tests

```bash
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=26.5" \
  -only-testing:Plinx-iOS-UnitTests \
  CODE_SIGNING_ALLOWED=NO
```

The home-screen regression gate is deterministic and does not require live
Plex credentials. It covers the full safety-filter-to-row-projection path,
including rated YouTube content, parental rating ceilings, the global unrated
toggle, and the Other Videos landscape row:

```bash
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.5" \
  -only-testing:Plinx-iOS-UnitTests/HomeRecentlyAddedProjectionTests \
  -only-testing:Plinx-iOS-UnitTests/RecentlyAddedHubClassifierTests \
  -only-testing:Plinx-iOS-UnitTests/SafeHomeViewModelTests \
  CODE_SIGNING_ALLOWED=NO
```

### Strimr integration contract

```bash
# Fast source-seam check
./scripts/verify_strimr_integration_contract.sh --quick

# CI-equivalent sibling checkout and history check
./scripts/verify_strimr_integration_contract.sh --full
```

Use `--full` when changing the Strimr pin, branch pairing, XcodeGen source
roots, or a Plinx↔Strimr seam. The focused `StrimrUpgradeSeamTests` remain the
behavioral coverage for testable upstream seams.

### Snapshot tests

```bash
./scripts/ui_tests.sh --snapshots
```

### Live UI smoke

```bash
./scripts/ui_tests.sh --live
```

### Live parity checks

```bash
./scripts/live_library_parity_tests.sh
```

### Release archive validation

```bash
./scripts/tests/validate_testflight_archive.sh ./build/Plinx.xcarchive
```

## What Lives Where

### `Packages/PlinxCore/Tests/`

Pure logic tests for safety-critical and domain behavior:

- `SafetyInterceptor`
- `SafetyPolicy`
- `MathGate`
- `PlinxRating`

### `Packages/PlinxUI/Tests/`

Component and layout verification:

- logic/layout tests
- snapshot tests
- theme/component coverage

See `docs/development/ui-testing.md` for structure and device coverage.

### `PlinxApp/UnitTests/`

App integration logic such as:

- settings behavior
- home/library grouping
- recently-added hub classification and complete movie/TV/Other Videos row projection
- layout policies
- safety adapters
- navigation coordination
- offline playback decisions
- parental authorization, download ownership, safe playlists, and playback-volume application

### `PlinxApp/UITests/`

Critical user path and rendering checks such as:

- launch smoke
- branding surfaces
- library browsing
- quick actions
- live rendering

### `PlinxApp/UnitTestsTV/`

Apple TV-specific policy and live parity coverage.

## Change Type To Test Guidance

| Change type | Minimum test expectation |
|---|---|
| Safety, ratings, parental gate, privacy-sensitive behavior | `PlinxCore` tests plus relevant app unit tests |
| Shared UI components, theme, asset-driven layout | `PlinxUI` tests plus snapshot tests |
| App navigation, adapters, view models, library/download logic | App unit tests plus any impacted package tests |
| Kid-facing flows, major UI behavior, or visible layout changes | Targeted UI tests and snapshot tests |
| Real-data browse/render behavior or Strimr integration changes | Live UI smoke and/or live parity checks where applicable |
| Release/archive/build pipeline changes | Archive validation and any touched script/workflow validation |

## Live Credentials

Live tests load credentials from repository-root `test_creds.yaml`, copied from `test_creds.yaml.example`.

Required keys for the main live path:

```yaml
PLINX_PLEX_SERVER_URL: "http://your-plex-server:32400"
PLINX_PLEX_TOKEN: "your-plex-auth-token"
```

Keep the real `test_creds.yaml` local only.

## CI Notes

- CI runs package tests, unit tests, and documentation guardrails.
- Live Plex-dependent tests are not part of normal CI and should be run locally when a change affects runtime rendering, playback, library behavior, or safety filtering against real data.

See `docs/development/ci.md` for workflow details.
