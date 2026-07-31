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
source scripts/build_environment.sh
swift test \
  --package-path Packages/PlinxCore \
  --scratch-path "$PLINX_SWIFTPM_SCRATCH_ROOT/PlinxCore"
```

### PlinxUI package tests

```bash
source scripts/build_environment.sh
swift test \
  --package-path Packages/PlinxUI \
  --scratch-path "$PLINX_SWIFTPM_SCRATCH_ROOT/PlinxUI"
```

### App unit tests

```bash
source scripts/build_environment.sh
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=26.5" \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  -only-testing:Plinx-iOS-UnitTests \
  CODE_SIGNING_ALLOWED=NO
```

The home-screen regression gate is deterministic and does not require live
Plex credentials. It covers the full safety-filter-to-row-projection path,
including rated YouTube content, parental rating ceilings, the global unrated
toggle, and the Other Videos landscape row:

```bash
source scripts/build_environment.sh
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.5" \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  -only-testing:Plinx-iOS-UnitTests/HomeRecentlyAddedProjectionTests \
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

The Youtarr Explore tab also has deterministic unit and UI regression coverage
that uses in-process catalog fixtures. It exercises tab selection, production
view mounting, response decoding, safety filtering, transactional refresh,
URLSession cancellation, and video-card rendering without a Youtarr or Plex
server. A cancelled activation or refresh must never appear as a network
failure, and a failed refresh must preserve an already-rendered catalog:

The focused tests also cover the 40-video initial catalog request, independent
catalog/channel failures, tail-triggered pagination, and long-press actions.
Offline-download policy tests cover both profile-owned downloads and
rating-gated shared legacy downloads created before ownership tracking.
`StrimrDownloadIntegrityTests` also locks the complete download-quality preset
mapping, original-quality request behavior, and rejection of structured error
payloads returned with a successful HTTP status.

Download-queue changes require a live Plex pass before release because CI does
not provision Plex Media Server. Run one direct-play-compatible title and one
forced-transcode title at a reduced preset. For each, verify the
deciding/preparing/downloading transitions, final offline playback, relaunch
recovery during preparation, profile-switch isolation, explicit deletion, and
server queue cleanup. Repeat the original preset to confirm no bitrate or
resolution cap is sent.

```bash
source scripts/build_environment.sh
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.5" \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  -only-testing:Plinx-iOS-UnitTests/YoutarrFoundationTests \
  -only-testing:Plinx-iOS-UnitTests/YoutarrExploreTests \
  -only-testing:Plinx-iOS-UITests/YoutarrExploreOfflineUITests \
  CODE_SIGNING_ALLOWED=NO
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
- canonical library-catalog loading and complete movie/TV/Other Videos row projection
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
