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

The home-screen and content-safety regression gate is deterministic and does
not require live Plex credentials. It covers the safety boundary every provider
goes through and the row projection on top of it, including rated YouTube
content, parental rating ceilings, the global unrated toggle, the Other
Videos landscape row, and the My Favorites row (`HomeFavoritesStoreTests`:
blocked titles, hidden libraries, and favorites loaded under an earlier
policy):

```bash
source scripts/build_environment.sh
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.5" \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  -only-testing:Plinx-iOS-UnitTests/HomeRecentlyAddedProjectionTests \
  -only-testing:Plinx-iOS-UnitTests/HomeFavoritesStoreTests \
  -only-testing:Plinx-iOS-UnitTests/SafeMediaServicesTests \
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
engine's asynchronous seek or completion behavior.

### Content-safety boundary

`SafeMediaServicesTests` is the conformance test for the boundary in
`PlinxApp/Core/Safety`. A fake provider returns an allowed title and a blocked
one from every content call and from its offline caches; the test fails if
the blocked title ever leaves `SafeMediaServices`. It also parses the provider
protocols in `PlinxApp/Core/Services/Protocols`, the offline cache protocols
(`OfflineHomeCacheReading`, `OfflineDetailCacheReading`) and
`AccountPreferencesService`, and fails when a requirement is missing from
`SafeMediaServices.reviewedRequirements`. It parses the services
`MediaServices` stores as well, and fails when one is declared as a protocol
that the table does not review. Run it, plus `PlinxCore` tests, whenever you
change a provider protocol, a provider, `MediaServices`, `ContentSafetyGate`,
or rating normalization.

Tightening the policy applies at once. In `SafeMediaServicesTests`,
`test_tighterPolicyAppliesToLaterPagesOfListingsGatheredUnderTheOldOne`
pages every listing past its first page under a permissive policy, lowers it
to G and TV-Y without unrated titles, and checks that a later page holds no
title only the old policy allowed and is indexed and counted in the stricter
listing. `test_tighterPolicyAppliesToTheOfflineCaches` does the same for the
cached home and detail page, and
`test_homeRowsLoadedUnderAPermissivePolicyAreHiddenWhenItTightens` checks,
through the sample library, that `HomeViewModel.rows` drops rows loaded under
the permissive policy without a reload.

The server Manage menu is parent-only. In `SafeMediaServicesTests`,
`test_everyParentOnlyRequirementIsRefusedWhileLockedAndAnsweredOnceUnlocked`
calls every `gated` requirement through `MediaServices`, against a provider
and a management service that answer as an administrator's server would. With
the gate locked, each request is refused or answers empty or false, and none
reaches the provider. Once a parent unlocks the gate, each one reaches it.
`test_everyGatedRequirementHasAParentOnlyProbe` fails when a `gated`
requirement has no probe. `test_manageMenuIsEmptyAndRefusedWhileLocked`
checks that, with the gate locked, the card and detail menus get no Manage
entry on a server the account administers, and that delete, unmatch and
refresh do nothing. The UI test
`LaunchSmokeUITests/test_kidModeOffersNoManageMenu` opens the sample library
(`PLINX_UI_TEST_MODE=demo`) and checks that neither a card's quick actions nor
the detail page's More menu offers Manage, any of its actions, or the library
actions (Scan, Refresh All Metadata, Analyze Library, Empty Trash). Run both
when you change the Manage menu, `MediaQuickActions`, or the parental gate.

Both locks read `ContentSafetyGate.isParentUnlocked`, which
`ContentSafetyBoundary` keeps equal to the parental gate.
`ContentSafetyBoundaryTests` (in `ParentalAccessCoordinatorTests.swift`)
drives the coordinator with no view in between. It checks that an unlock
reaches the gate, that a lock clears it at once and denies server rights,
that swapping to the sample library's locked coordinator relocks it, and
that leaving the foreground relocks it. `ParentalSceneLockTests` in the same
file covers the relock on leaving the foreground and its bounded wait while
a Plex sign-in is in progress. Run them when you change the parental gate,
what relocks it, or `ContentSafetyBoundary`.

`ContentRatingNormalizerTests` (in `PlinxCore`) covers how ratings are parsed:
US movie and TV ratings in any case, prefixes such as `US-` and `Rated `, TV
content descriptors, trailing notes (including ratings written with spaces,
such as `PG 13 (US)`), adult-only ratings including age certificates above 18
(`KR-19`, `R21`, `21+`, `18A`) and their rejection when unrated content is
allowed, and the fallback to unrated for anything else.
`ContentSafetyGatePolicyTests` checks the same rules through
`ContentSafetyGate(policy:)`, the one way to judge titles against an explicit
policy: unrated, adult-only and over-the-ceiling titles, unrated episodes
judged against their series (and blocked when the series is unknown), hub
filtering, and the playlist Play and Shuffle selection.

Jellyfin titles carry two ratings. `JellyfinMappingTests` covers how
`JellyfinContentRating` picks the stricter of `OfficialRating` and
`CustomRating`, and that every Jellyfin `Fields` list asks for `CustomRating`.
`SafeMediaServicesTests.test_jellyfinCustomRatingAboveTheCeilingIsBlocked`
checks at the gate that a custom rating above the ceiling blocks a title whose
official rating is under it, and that a custom rating never loosens one.

Seasons and episodes are judged against their series. In
`SafeMediaServicesTests`,
`test_unratedEpisodesOfABlockedSeriesStayBlockedWhenUnratedContentIsAllowed`
gives the fake provider unrated and rated episodes and seasons (Plex and
Jellyfin shapes) of a TV-MA series, a TV-Y series, a series the provider
cannot find, and a lookup that answers with a movie. With unrated content
allowed, it checks every path that returns them (watching rows, search, hub
pages, season pages, favorites, playlist entries, season downloads, queues,
direct lookups) and that each series is looked up once.
`test_anUnratedEpisodeTakesItsSeriesRating`,
`test_aSeriesListedWithItsEpisodesIsNotLookedUp`, and
`test_learnedSeriesRatingsAreKeptForOfflineChecks` cover the inherited
rating, the lookups a listing makes unnecessary, and the on-device
`SeriesRatingStore` that judges downloads offline.
`test_containersAreListedWithoutTheServerArtworkOfTheirEntries` checks that
collections and playlists leave the boundary without the server composite
and counts. Run them when you change `ContentSafetyGate`, a wrapper in
`SafeContentServices`, or how a provider maps series, seasons, episodes or
containers.

`PlaybackLauncherTests` covers `PlaybackLauncher`, the final check before the
player opens. Its fake services let every title through the boundary, so each
refusal comes from the launcher: a title the fresh lookup finds over the
ceiling, a queue whose next episode is over the launcher's gate (the kid
ceiling, or a stricter `ContentSafetyGate(policy:)` a caller passes), unrated
episodes of a blocked or unknown series (an unrated episode of an allowed
series plays), a playlist with a blocked entry (the starting entry,
one re-rated since the list loaded, or a later one), and a cancelled launch
(by the caller or by its task), none of which presents the player. Offline, a
stub `OfflinePlaybackSource` hands the launcher downloads it must refuse: one
of another profile or with no owner, one whose pinned server metadata or a
stricter launcher gate blocks it, and one that is unfinished or from another
server.
Allowed controls on the same fixtures fail if the launcher refuses everything,
so no refusal passes for that reason alone. Run it when you change
the launcher, `PlaybackQueue`, `DownloadAccessPolicy`, or a playback entry
point.

`DownloadOwnershipMigrationTests` covers the one-time move of the per-profile
records that earlier versions kept in `plinx.downloadOwnership.v1` onto each
download's owner, and checks that a download with no record stays unowned.
It also drives `LegacyDownloadIndex.migrate` with a temporary `index.json` and
a test offline database: an entry's `accessScope` becomes its owner, an empty
server or profile, another server, or a stray `ownerID` never does, and a
damaged entry is dropped on its own and defers the ownership import. The
offline resume points that index kept move into the owner's offline progress
once, never over more recent progress.

`MultiServerMigrationTests` checks that the libraries hidden before the update
stay hidden for every profile: a second Plex Home user that appears after the
update, an account whose token was revoked, a Jellyfin server without a token,
and a list whose server is only known from the first Plex server list.
`ProfileSettingsTests` covers the family's library settings themselves, and
`SettingsManagerPlaybackTests` checks them through `PlinxLibraryVisibility`.
It also checks that a library load for one profile, which lists only the
libraries that profile can see, never removes a library another profile or
the family hid.

Changes to `PlinxApp/Core` or `PlinxApp/Platform` are ordinary Plinx changes:
build both app targets and run the unit tests for the touched area. There is
no separate integration contract. The live parity tests below cover real
server content.

`PlinxApp/CoreTests` holds upstream's tests for the absorbed code. They are
compiled into the `Plinx-iOS-UnitTests` target, so they run with the app unit
tests above and in CI. Keep them passing when you change `PlinxApp/Core` or
`PlinxApp/Platform`. When a Plinx change alters upstream behavior on purpose,
update the upstream test in place rather than skipping it.

### Compiling and running

Compiling needs no simulator runtime. Build the app targets and their test
bundles for a generic destination (`generic/platform=iOS Simulator` or
`generic/platform=tvOS Simulator`, with `ARCHS=arm64`); see
[setup](setup.md#compile-without-a-simulator-runtime). Running unit tests, UI
tests, or the app needs an installed simulator runtime and a concrete device
destination, as in the commands above.

UI-test and screenshot launch hooks work only in Debug builds; see
[UI testing](ui-testing.md#debug-builds-only).

### Tooling contracts

```bash
bash scripts/tests/test_tooling_contracts.sh
```

It checks the test runners, credential loading, simulator runner preflight,
and the corresponding-source bundle (`scripts/build_compliance_bundle.sh`) in
throwaway fixtures. Run it after changing any of those scripts.

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
`OfflinePlaybackTests` covers download access: only the active profile's
owned downloads that the content policy allows are playable, and downloads
with no owner are refused. `OfflineEpisodeChainingTests` covers offline
next-episode chaining, which uses the same `DownloadAccessPolicy` decision: an
episode of another profile, without an owner, or whose stored or pinned
metadata fails the gate never plays next. `DownloadIntegrityTests` covers
`DownloadIntegrityValidator` and the reason a failed download row shows, the
20 percent space-savings rule
(`DownloadSpaceSavingsPolicy`), and the mapping of the old Plinx
download-quality setting to a quality preset.

Download-queue changes require a live Plex pass before release because CI does
not provision Plex Media Server. Run one direct-play-compatible title and one
forced-transcode title at a reduced preset. For each, verify the
preparing/downloading transitions, final offline playback, relaunch
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
- `ContentRatingNormalizer`

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
- the content-safety boundary (`SafeMediaServicesTests`) and content rules
- the final playback check (`PlaybackLauncherTests`)
- navigation coordination
- offline playback decisions
- parental authorization, download ownership and its migration, safe
  playlists, and playback-volume application
- Jellyfin server search availability on iPhone and iPad
  (`JellyfinServerDiscoveryAvailabilityTests`; see "Entitlements" in
  `docs/development/setup.md`)

### `PlinxApp/CoreTests/`

Upstream's tests for the absorbed code, compiled into the
`Plinx-iOS-UnitTests` target and run with the app unit tests.

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
| Real-data browse/render behavior, providers, or session code in `PlinxApp/Core` | Live UI smoke and/or live parity checks where applicable |
| Provider protocols, providers, or the content-safety boundary | `SafeMediaServicesTests` plus `PlinxCore` tests |
| `PlinxPlaybackLauncher`, playback queues, or a playback entry point | `PlaybackLauncherTests` plus `SafeMediaServicesTests` |
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

On iPhone and iPad, the **Sign-in information** button on the first
connection screen opens login guidance and **Explore the Demo Library**. On
Apple TV the Plex sign-in screen offers the same action. Both appear only
while no account exists. The sample library is a temporary Plex account added
to the real `SessionManager`, so it runs the production server registry,
content-safety boundary, LibraryStore, browse/detail/search views, playback
authorization, player, and download flows against fictional
`DemoFixtureCatalog` responses. `DemoMediaServer`, a Plinx-owned service bound
only to `127.0.0.1`, serves the original bundled MP4s in
`PlinxApp/Resources/DemoMedia` with byte-range support. `PlexCloudStandIn`
answers plex.tv requests that carry the sample token on the device. There is
no Plex account or external media dependency. Leaving the sample library
removes the account; an account left behind by a killed app is removed at the
next launch.

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
through the production catalog loader, TV season/episode ratings,
the on-device plex.tv stand-in, sample request lifecycle over HTTP, preference
isolation, and a production download owned by the sample profile followed by
file playback after stopping the sample server. The production download test
uses the host app's manager and deletes its sample file afterward.

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
gravity; it does not resize the player hierarchy or change the AetherEngine pin.
The focused player UI check also verifies that the landscape timeline centers
on the display and that Settings remains tappable in the reclaimed status area.
Inset policy tests cover both sidebar sides, portrait, and ordinary phone notches.

## CI Notes

- CI runs package tests, unit tests, and documentation guardrails.
- Live Plex-dependent tests are not part of normal CI and should be run locally when a change affects runtime rendering, playback, library behavior, or safety filtering against real data.

See `docs/development/ci.md` for workflow details.
