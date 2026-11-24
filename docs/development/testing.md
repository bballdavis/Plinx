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
  -only-testing:Plinx-iOS-UnitTests/SeasonDownloadSelectionTests \
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

### Player timeline regression checks

`PlayerTimelineTests` is shared by the iOS and tvOS app unit targets. It covers
timeline geometry, invalid values, endpoint touch targets, drag offsets, and
editing-session lifecycle. `PlayerTimelineUITests` runs the production view in
the deterministic `playerTimeline` screen (`--ui-testing` and
`PLINX_UI_TEST_SCREEN=playerTimeline`) on both platforms. Touch tests reject
track/handle taps and drag through both endpoints; TV tests verify directional
steps, commitment, and focus navigation. Screenshots are attached to results.

After regenerating the project, use an installed simulator destination:

```bash
source scripts/build_environment.sh
xcodebuild test -project PlinxApp/Plinx.xcodeproj -scheme Plinx-iOS \
  -destination 'platform=iOS Simulator,name=Plinx iPhone 17 Pro (26.5)' \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  -only-testing:Plinx-iOS-UnitTests/PlayerTimelineTests \
  -only-testing:Plinx-iOS-UITests/PlayerTimelineUITests CODE_SIGNING_ALLOWED=NO

xcodebuild test -project PlinxApp/Plinx.xcodeproj -scheme Plinx-tvOS \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  -only-testing:Plinx-tvOS-UnitTests/PlayerTimelineTests \
  -only-testing:Plinx-tvOS-UITests/PlayerTimelineUITests CODE_SIGNING_ALLOWED=NO
```

Also verify iPhone landscape, iPad, VoiceOver, Reduce Motion, bright/dark
video backgrounds, and real streamed/downloaded playback before release.
Seek to zero and duration while playing and paused and confirm normal
completion/next-item behavior. The fixture validates UI callbacks, not an
engine's asynchronous seek or completion behavior. Changing timeline source
exclusions requires the full integration contract below.

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

`scripts/verify_release_dependency_state.sh` separately compares the sibling
source with the exact Git archive. It excludes local build/tool metadata,
including `.code-review-graph/`, while still rejecting source differences.
`scripts/tests/test_tooling_contracts.sh` checks both cases in isolated fixtures.

### Snapshot tests

```bash
./scripts/ui_tests.sh --snapshots
```

### Live UI smoke

```bash
./scripts/ui_tests.sh --live
```

The Youtarr Explore tab has a required synthetic HTTP integration gate:

```bash
./scripts/tests/youtarr_synthetic_ui_tests.sh
```

The runner mounts Youtarr's real external API router over the canonical
sanitized dataset; it does not start the full Youtarr app or a database. Plinx
uses its production HTTP client and UI to verify authentication, query and
response compatibility, safety filtering, artwork, details, request writes,
request lifecycles, cancellation, and explicit empty/error states.

The unit-test bundle also contains Youtarr's canonical sanitized external API
fixture. Before changing the client contract, verify that the vendored fixture
matches the pinned producer revision:

```bash
./scripts/verify_youtarr_contract_fixture.sh --check
```

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
  -only-testing:Plinx-iOS-UnitTests/YoutarrContractFixtureTests \
  -only-testing:Plinx-iOS-UnitTests/YoutarrFoundationTests \
  -only-testing:Plinx-iOS-UnitTests/YoutarrExploreTests \
  -only-testing:Plinx-iOS-UnitTests/YoutarrRequestTests \
  -only-testing:Plinx-iOS-UITests/SeasonDownloadOfflineUITests \
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

## Parental PIN Keyboard

`BrandingUITests/test_parentalPIN_numericKeyboardAndDoneStayVisible` uses an
isolated PIN fixture to check that tapping the field exposes tappable numeric
keys, Done stays inside the screen, an incorrect PIN keeps the gate locked,
and the correct PIN unlocks it. Enable Simulator's software keyboard before
running this interaction check; hardware-keyboard mode can keep the requested
number pad offscreen. The fixture never reads or changes the family's PIN.

## App Review Demo Fixtures

The connection screen on iPhone, iPad, and Apple TV includes **Explore the
Demo Library**. On iPhone/iPad the **Sign-in information** button opens login
guidance and the same action. It runs the production SessionManager,
LibraryStore, browse/detail/search views, safety decorators, playback
authorization, player, and download flows against fictional
`DemoFixtureCatalog` responses. `DemoMediaServer`, a Plinx-owned service bound
only to `127.0.0.1`, serves the original bundled MP4s in
`PlinxApp/Resources/DemoMedia` with byte-range support. There is no Plex account
or external media dependency, and the demo session is never persisted. tvOS
SessionManager mirrors tokens into Top Shelf storage only when the bundle
declares `TopShelfKeychainAccessGroup`; Plinx ships no Top Shelf extension, so
the demo is enabled on Apple TV too.

The sample movie/episode are 90 seconds with visible motion/time, two quiet
audio tracks, and captions. Regenerate them on macOS using
`python3 scripts/release/generate_demo_media.py /path/to/ffmpeg`.
FFmpeg is a development tool only; the app bundles the generated media.
The sample JSON Youtarr catalog is in the same resource directory, with
in-memory request mutations and no external download scheduling.

The XcodeGen resource patcher must include the `DemoMedia` folder in the iOS
and tvOS resource phases. Regenerate the project after resource/source changes.
Fixture ratings deliberately span the parental controls (see the reviewer
table in `docs/release/app-store.md`); keep that table and these tests in sync.
`DemoFixtureTests` checks real media tracks, HTTP byte ranges, episode queue
identity, mixed-rating filtering, every movie/TV ceiling pair and both unrated modes
through the production catalog loader, TV season/episode rating propagation,
sample request lifecycle over HTTP, preference
isolation, and a production download followed by file playback after stopping
the sample server. The production download test uses the host app's manager
and deletes its sample file afterward.

Run `LaunchSmokeUITests/test_demoModeRendersProductionHomeAndRealPlayback` on
both iPhone and iPad. It verifies help can be dismissed without starting a session, enters via
information → Explore the Demo Library, captures both sign-in/help, and checks
the production player controls. The engine integration test separately checks
real progression, seeking, pause, and the volume limit. It saves a player screenshot.
Also perform the fresh-install release checklist in the
[review runbook](../release/app-store.md#reviewer-access). The demo PIN is 2468;
demo preferences/PIN reset on entry, while sample downloads persist until
removed.

`--ui-testing` with `PLINX_UI_TEST_MODE=demo` enters the demo at launch. On
tvOS, `AppleTVRemoteWalkUITests` replays a scripted Siri Remote walk against
the demo and saves a screenshot and the focused element after each press:

```bash
TEST_RUNNER_PLINX_REMOTE_WALK="down,right,select,wait,menu" \
TEST_RUNNER_PLINX_REMOTE_WALK_DIR="$PWD/build/remote-walk" \
xcodebuild -project PlinxApp/Plinx.xcodeproj -scheme Plinx-tvOS \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  test -only-testing:Plinx-tvOS-UITests/AppleTVRemoteWalkUITests
```

The walk is skipped when no script is supplied, so normal test runs are
unaffected.

## Expanding iPhone display checks

For iPhone Duo layout changes, check both Closed and Open in Device Hub, then
open and close the device during playback. Confirm the video resizes without
restarting, the timeline and Back/Settings controls remain visible, and exiting
playback restores the browse navigation. Check Home, Library, and Explore for
continuous ambient backgrounds underneath the side status area. Repeat the
player check on a conventional iPhone in portrait and landscape and on iPad.

The Duo simulator has multiple displays. If the screenshot tool cannot select
one, use `xcrun simctl io <UDID> screenshot --display=<display-id> <output.png>`;
the error from an unqualified capture lists the available display IDs. Capture
the active display rather than interpreting an inactive black display as a
rendering failure. `PlinxPlayerControlLayoutTests` covers the geometry-driven
chrome spacing independently of a model identifier.

`LaunchSmokeUITests/test_playerFitFillSurvivesHiddenControls` launches the
production demo player directly through the `demoPlayer` UI-test screen. It
switches Fit to Fill and back, checks that Fill survives hidden controls, and
captures both modes for visual inspection. Player layout unit tests
exercise native and sample-buffer video layers, late layer attachment, a
renderer replacement, source gravity resets, and observer teardown. The Plinx
adapter identifies Aether's public render view and updates AVFoundation video
gravity; it does not resize the player hierarchy or change the paired Strimr pin.
The focused player UI check also verifies that the landscape timeline centers
on the display and that Settings remains tappable in the reclaimed status area.
Inset policy tests cover both sidebar sides, portrait, and ordinary phone notches.

## CI Notes

- CI runs package tests, unit tests, and documentation guardrails.
- Live Plex-dependent tests are not part of normal CI and should be run locally when a change affects runtime rendering, playback, library behavior, or safety filtering against real data.

See `docs/development/ci.md` for workflow details.
