# Strimr Hard-Fork Plan

Decision date: 2026-11-23. This is a plan. Nothing described here has landed
yet. The paired sibling checkout, `config/release-dependencies.env`, and the
rules in `AGENTS.md` stay in force until the fork-day change replaces them.

## Decision

Plinx will **hard fork Strimr**: Strimr's source moves into the Plinx
repository and becomes Plinx code. The sibling checkout, the Strimr pin, the
`dev-plinx` pairing branch, and the source-token seam contract all go away.
Upstream Strimr becomes a feature feed that Plinx reviews and ports from on
purpose.

**Why:**

- **Shape-matching overrides break on every upgrade.** Plinx compiles about
  22k (iOS) to 23k (tvOS) lines of Strimr into its app module. It overrides
  Strimr by excluding files and declaring same-named types, with 27 type-name
  collisions and 42 seam tokens. Any upstream rename or new parameter breaks
  the build. In the 2026-11 audit, only 5 of 25 trial cherry-picks applied
  cleanly.
- **Plinx is no longer a thin skin.** Plinx owns about 28.5k lines of app code
  and 10.9k lines of tests, more than the Strimr code it compiles.
- **Owning the code makes safety structural.** Plinx can delete what it will
  never ship, and filter every content source at one boundary instead of in
  six view-model wrappers plus view-level checks.

**Fork base:** current upstream (audited at `0235d27`, 2026-11-21), not the
current pin. Plinx now wants most of upstream, including Jellyfin, Seerr and
the Manage menu. Porting the provider layer onto the old pin would redo the
whole migration piece by piece. The [commit triage](strimr-contributions/15-upstream-main-migration-plan.md)
classifies all 282 commits since the old base.

## Decisions Before Fork Day

| # | Decision | Recommendation | Why |
|---|---|---|---|
| D1 | OS minimums | Raise to iOS 18, iPadOS 18 and tvOS 18 | Upstream (#192) and its AetherEngine revision require 18. iOS 18 and tvOS 18 run on the same iPhones and Apple TVs as iOS 17 and tvOS 17; iPadOS 18 drops only the 7th-generation iPad. Confirm against Apple's current support lists before writing release notes |
| D2 | Xcode | Already 27.2 (`51c556e`) | No action needed |
| D3 | Trakt and Simkl | Exclude | Sends children's viewing history to third parties. Zero collection is the baseline, and `AGENTS.md` requires an explicit privacy decision before adding trackers |
| D4 | External players | Exclude | Policy: handing playback to another app bypasses content checks and the volume cap |
| D5 | Live TV | Exclude in v1. Later, parent-approved channels only | Program and channel models carry no rating, so per-item filtering cannot fail closed |
| D6 | Top Shelf | Exclude in v1. Later, read a filtered cache | Upstream's extension fetches over HTTP directly, bypassing every filter |
| D7 | macOS | Exclude | No product scope |
| D8 | Seerr | Adopt with the kid model below | Requested feature. Needs certification filtering and per-kid attribution |
| D9 | Manage menu | Adopt behind the parental gate | Requested feature. All settings are already parent-gated |
| D10 | Fork location | Plinx repository, under `Strimr/` | One repository, one source offer, no pairing |

## Target Architecture

### Repository layout

```text
PlinxApp/            app shells, Plinx screens, App Review demo
Strimr/              vendored upstream, edited in place (no shadows, no seams)
  Shared/  Strimr-iOS/Features/  Strimr-tvOS/  LICENSE  UPSTREAM.md
Packages/PlinxCore   safety policy, rating normalization, parental logic
Packages/PlinxUI     brand, theme, loading, focus
```

`Strimr/UPSTREAM.md` records the fork base commit, the date of the last
feature review, and a link to the triage. `config/release-dependencies.env`
keeps the AetherEngine pin, and a `STRIMR_FORK_BASE` value replaces the
`STRIMR_*` pairing keys so the documentation dependency loader still renders
the base revision.

Keep upstream's directory layout under `Strimr/` for the first two or three
feature reviews. Then `git cherry-pick -x -X subtree=Strimr <commit>` still
applies most upstream fixes directly. Restructure only after that window (see
"Later: module boundaries").

### One safety boundary

Upstream now has a provider seam: `MediaServices`
(`Shared/Services/MediaServices.swift`), assembled from the protocols in
`Shared/Services/Protocols/MediaServiceProtocols.swift`. Each provider builds it
in one place: Plex in `PlexMediaServices.swift`, Jellyfin in
`JellyfinMediaServices.swift`.

Add a Plinx `SafeMediaServices` that wraps every content-returning service at
those construction points, on **every platform** (upstream's offline decorators
skip tvOS):

| Service | Plinx filtering |
|---|---|
| Home, library, search, hub detail | Drop items that fail `SafetyInterceptor`; drop hubs that end up empty; compact pagination |
| Detail (seasons, episodes, collections, person filmography, extras) | Same filter. A detail lookup for a blocked item returns "not found" |
| Favorites, playlists | Filter entries; writes are allowed only where the feature table says so |
| Playback (queue, autoplay, post-play) | Every queue member re-checked; `PlinxPlaybackLauncher` stays the final check |
| Downloads | Ownership scoping (server plus profile or user) plus the current policy |
| Live TV, DVR | Not wired in v1 |
| Management | Present only while the parental gate is unlocked |

Seerr has no service protocol upstream; its view models build repositories
directly (`SeerrDiscoverViewModel`, `SeerrMediaDetailViewModel`,
`FeaturedTrendingLoader`, and others). Add a `SeerrCatalogService` protocol so
Seerr goes through the same wrapper.

This replaces six `Safe*ViewModel` decorators (676 lines), most of
`StrimrAdapter` (205), the `itemFilter`/`hubFilter` seams, and the view-level
filtering. New upstream screens are then filtered without any extra work. When
a parent changes the rating ceiling, the wrapper publishes an invalidation and
upstream's fresh-data refresh reloads the visible screens.

**Conformance test:** a fake provider returns one allowed item and one
over-ceiling or unrated item from every protocol method. A table-driven test
asserts that the blocked item never leaves `SafeMediaServices`. Any new
protocol method that isn't listed in the table fails the test.

### Rating normalization

`MediaItem.contentRating` already carries Plex `contentRating` and Jellyfin
`OfficialRating`. Upstream never filters on it.

- `PlinxRating` parsing moves to a normalizer in `PlinxCore` that accepts US
  movie and TV systems, common prefixes (`US-`, `Rated `), and the forms Plex
  and Jellyfin produce. Anything else is rejected, which keeps today's
  fail-closed default.
- Add other national systems only with tests and a parent-visible mapping.
- Map Jellyfin tags to Plinx labels so label-gated libraries work the same way
  on Jellyfin.

## Feature Plan

Apply the "kid app, but useful" test to every feature.

| Feature | Stance | Kid-facing behavior | Work |
|---|---|---|---|
| **Jellyfin** (#148 and follow-ups) | Adopt | Same filtered browsing as Plex | Onboarding source picker. Quick Connect first on Apple TV. Normalize ratings. Read `Policy.MaxParentalRating` and `BlockUnratedItems` (not decoded upstream) and suggest a kid Jellyfin user with server-side limits as a second layer |
| **Multi-server** (#200) | Adopt | Merged home across servers, each item filtered | Key download ownership by account plus server. Generalize `OfflineSessionSnapshot` from Plex-only to an account |
| **Seerr** (#235 and later) | Adopt | "Ask a grown-up" requests | See the Seerr kid model below |
| **Manage menu** (#337–#349) | Parent-only | Never rendered in kid mode | Entries render only while `ParentalAccessCoordinator` is unlocked. Delete, empty trash and unmatch need a fresh PIN and confirmation every time |
| Chapters, scrub thumbnails, skip segments, end time (#117, #119, #120, #316) | Adopt | Yes | Fold into the Plinx timeline (see below) |
| Multi-version, editions, track memory, subtitle styling, ASS (#190, #303, #175, #373, #128) | Adopt | Yes | `swift-ass-renderer` license review |
| Sleep timer, default sleep timer (#206, #341) | Adopt | Yes | Offer as a parent "bedtime" setting |
| Night mode, dialogue boost (#358) | Adopt | Yes | Kid-friendly audio |
| Theme music (#229) | Adopt | Yes | Parent toggle |
| Autoplay and post-play (#159) | Adopt | Yes, every next item re-checked | Parent toggle; launcher test for an over-ceiling next episode |
| Favorites (#161) | Adopt | Yes, a filtered "My favorites" row | Writes allowed; harmless |
| Playlist management (#257) | Parent-only | Kids see filtered playlists only | Edits gated |
| Remove from Continue Watching (#336) | Adopt | Yes | Harmless account write |
| Subtitle search and auto-apply (#133, #376) | Parent-only | No | Writes to the server |
| Picture in Picture, background audio (#145, #367) | Parent setting, default off | Only if a parent enables it | — |
| 15-minute profile re-prompt (#419) | Through the parental gate, or disabled | Never offers adult profiles | — |
| Offline mode, downloads before sign-in (#186, #154) | Adopt one offline system | Only the active profile's downloads | Upstream offline (`Shared/Offline`, 4.3k lines) overlaps Plinx's offline access coordinator; keep one (see Shrink) |
| iPhone Duo, pinch zoom, auto-rotate, PiP (#258–#260, #251, #250) | Adopt | Yes | — |
| Home hero carousel, extras, person pages, folder tree, shared items (#365, #174, #121, #202, #328) | Adopt | Yes, filtered by the boundary | No extra seams needed once the boundary exists |
| tvOS system player style (#413) | Exclude | Plinx player only | Bypasses Plinx chrome and the timeline |
| Default playback speed (#334) | Exclude | — | Plinx removed speed control |
| About, licenses, privacy (#263) | Parent-only | No external links in kid UI | Reuse the license list for compliance |
| Screenshot demo mode (#272) | Evaluate | — | See the demo item under Shrink |
| Trakt, Simkl, external player, Sentry, macOS | Exclude | — | Delete on fork day (see below) |
| Live TV, Top Shelf | Later | Parent-approved channels; filtered cache | Phase 8 |

### Seerr kid model

What upstream does (from source at `0235d27`):

- **Authentication** is a cookie session. Plinx posts to `auth/plex` with a Plex
  token, `auth/local`, or `auth/jellyfin`; there's no API key. The cookie lives
  in `HTTPCookieStorage.shared`.
- **Request payloads** carry no user field, so a request is attributed to the
  signed-in Seerr user (inferred from source, not yet verified on a live
  server).
- **Permissions** are a bitmask (`SeerrPermissionService`); admin overrides
  everything.
- **Discover and search models** expose no certification, adult flag or rating.

Plinx model:

1. **One Seerr user per kid.** Plinx signs in to Seerr with the *active
   profile's* identity: the kid's Plex Home token or the kid's Jellyfin user. A
   request is therefore owned by the kid's Seerr user, not by the parent.
2. **Keep profiles separate.** Use a separate cookie storage per profile
   instead of `HTTPCookieStorage.shared`, and clear it on profile switch and
   sign-out.
3. **Show the Seerr user to parents.** Parent settings show the signed-in Seerr
   user and its permissions. Warn when that user can auto-approve, manage
   requests, or is an admin. Recommended setup: request permission only, so
   every request waits for a parent.
4. **Filter discovery and fail closed.** Fetch each title's certification from
   Seerr's detail endpoints (movie release-date certifications and TV content
   ratings, for the Seerr region). Upstream models don't decode these fields,
   so verify them against the deployed Seerr version. Cache by TMDB ID. Never
   show a title until its certification is known and allowed. Always drop
   TMDB-adult results. Expect one detail request per uncached discover item;
   prefetch and cache per page.
5. **No outside links.** Trailers and external links are hidden in kid UI.
6. **Approvals.** In v1, parents approve in Seerr itself, through a link from
   parent settings. Later, add in-app approvals using a separate parent Seerr
   session. Upstream already has approve and decline calls
   (`SeerrManageRequestsViewModel`).
7. **Fold Youtarr in.** Plinx's Youtarr request flow (about 4.5k lines in
   `App/Youtarr` and `Views/Youtarr`) is the same "kid asks, parent approves"
   pattern. Share one request-status model and UI between Seerr and Youtarr.

### Player timeline

After the fork, the Plinx raised-hump timeline *becomes* `PlayerTimelineView`.
Edit Strimr's file in place instead of shadowing it. Accept upstream's full
parameter list:

- chapters
- skip segments
- scrub preview
- end time
- the tvOS scrub interaction (`onCancel`, `swipesScrub`, `onIdleSwipe`)

Render chapters and skip segments as spans along the curve. The tabletop (Duo)
layout becomes another caller. The timeline section of the
[triage](strimr-contributions/15-upstream-main-migration-plan.md) lists the
details.

## Fork Day

1. Ship the current test build first.
2. `git remote add strimr-upstream https://github.com/wunax/strimr`, then
   `git subtree add --prefix=Strimr strimr-upstream <base> --squash`.
3. Delete, rather than gate:

   | Path | Lines |
   |---|---|
   | `Strimr-macOS` | 5,867 |
   | `StrimrTopShelf` | 508 |
   | `Shared/Trackers` | 2,082 |
   | `Shared/Features/LiveTV` (v1) and the Live TV services | 3,753 plus services |
   | `ExternalPlayerApps`, `ExternalPlaybackCallbackHandling`, `CustomExternalPlayerView` | — |
   | Sentry `ErrorReporter` and the `sentry-cocoa` package | — |
   | Strimr app entry points, `ContentView`, `MainTabView` (Plinx owns the shells) | — |
   | `fastlane`, Strimr CI workflows | — |
   | `Screenshots` | 6.4 MB of images |

4. Remove the tracker call sites in about 15 files (`SessionManager`,
   `PlayerViewModel`, `MediaQuickActions`, offline progress, settings, app
   entry points) instead of stubbing them. In a fork, deleting is cleaner than a
   no-op `TrackerCoordinator`.
5. Replace hard-coded `Strimr` product identity strings with the host-app
   identity. Keep Strimr attribution in licenses.
6. Point `project.yml` at `Strimr/`. Delete every `excludes` entry that existed
   only to shadow a type, and merge each Plinx replacement into the original
   file.
7. Remove the pairing machinery: see "Pairing machinery" under Shrink.
8. **Exit criteria:** iOS and tvOS build and pass tests; archive validation shows
   no Sentry, Trakt or Simkl strings and the privacy manifest is unchanged.

## Shrink Review

Measured on 2026-11-23. Line counts are from `wc -l`. Dead-code findings are
from token search, so confirm each with a build before deleting.

### What gets smaller

| Area | Today | After | How |
|---|---|---|---|
| Shadow replacements | ~2.2k Strimr lines excluded and replaced by ~5.7k Plinx lines; 27 type-name collisions | One implementation per type | Merge Plinx versions into the originals: timeline, player controls and buttons (both platforms), track selection, launcher, `MediaBackdropGradient`, `MediaRatingLabel`, sign-in, profile and server selection, settings downloads view |
| Safety plumbing | 6 `Safe*ViewModel` decorators (676) + `StrimrAdapter` (205) + filter seams + view-level filters | One `SafeMediaServices` plus a conformance test | See the safety boundary above |
| Unreachable Strimr screens | 22 compiled files (3,154 lines) with no outside reference (Strimr Home, Library, Search, Collection, Playlist, Seerr and tvOS equivalents) | Deleted | Reachable only through Strimr entry points Plinx excludes. Confirm with a build |
| Excluded upstream areas | — | ~12.2k lines not carried | macOS, Top Shelf, Trackers, Live TV (figures above) |
| Pairing machinery | `verify_strimr_integration_contract.sh` (147), Strimr keys in `release-dependencies.env`, `verify_release_dependency_state.sh` (44), `scripts/strimr/run_ipad_sim.sh` (159), CI clone steps in `build.yml` and `xcode-project.yml`, `docs_guard`/tooling assertions, `branch-pairing.md` (143), 16 contribution plans, `StrimrUpgradeSeamTests` (81) | Removed or archived | Docs move to "Maintaining the fork" |
| `ErrorReporter` | Sentry version excluded, no-op copy declared | Call sites removed | A fork doesn't need the indirection |
| `PlinxSettingsSanitizer` | Forces Strimr defaults at launch | Defaults set in the source | Edit `AppSettings` defaults directly |

### What moves out of the release binary

About 2.56k lines in 15 harness, fixture and screenshot files ship in the app
today. They're gated only at runtime by environment variables and launch
arguments, with no `#if DEBUG` anywhere in `PlinxApp`. Examples:

- `AppleTVBrowseFocusUITestHarness` (482)
- `AppleTVPresentationUITestHarness` (254)
- `DownloadUITestFixtures` (172)
- `LivePlexUITestBootstrap` (126)
- `SeasonDownloadUITestBootstrap` (110)
- `PlayerTimelineUITestHarness` (110)
- the Youtarr test bootstraps
- `ParentalGateUITestHarness` inside `PlinxContentView.swift`

Move them behind `#if DEBUG` or a UI-test-only source group. Keep the App
Review demo (`DemoFixtureBootstrap`, `DemoMediaServer`), which is a product
feature.

### Demo simplification

Plinx's demo runs a loopback HTTP server (`DemoMediaServer`) that mimics Plex.
After the fork, a demo provider can implement `MediaServices` in-process, as
upstream's DEBUG-only `DemoMediaService` does. That removes the HTTP server and
fixture routing while keeping the 127.0.0.1-only, no-external-host guarantee
trivially true. Evaluate this after the safety boundary lands, because the demo
must exercise that same boundary.

### Offline: keep one system

Upstream's offline mode (`Shared/Offline`: GRDB store, `OfflineCoordinator`,
`ProgressSynchronizer`, service decorators) overlaps Plinx's
`PlinxSessionAccessCoordinator`, `OfflineSessionStore` and offline Downloads
root. Keep upstream's store and progress sync. Keep Plinx's ownership scoping
and its launch rule: show loading while connecting, and show offline only on
failure or when the device has no network. That likely retires most of Plinx's
offline plumbing and downstream patch 08.

### Duplication and dead code

- **Duplicated card logic.** `LibraryMediaCards` and `PlinxHomeCards` (219 and
  210 lines) should share one card view.
- **Overlapping settings screens.** `VisibleLibrariesView` and
  `LibraryViewsSettingsView` overlap. Plinx settings (2.8k lines) also overlap
  upstream settings (3.7k lines). After the fork, keep one settings tree:
  upstream sections behind the parental gate, plus Plinx's parental, rating and
  library sections.
- **Near-identical upstream settings views.** The iOS and tvOS versions of
  `SettingsInterfaceView`, `SettingsPlaybackView`, `SettingsSubtitlesView` and
  `SettingsView` differ by under 10 lines each. Unify them.
- **Duplicate tests.** The `MathGate` XCTest and Swift Testing files duplicate
  each other; keep one.
- **Dead declarations.** `SpringyButtonStyle`, `TvHeroIdentityView`,
  `PlinxPlaceholderView`, and `MockPlexServer` (a mock shipped in the
  production `PlinxCore` target). Each appears only in its own declaration.
- **Unused package API.** 9 `PlinxCore` and 17 `PlinxUI` public types have no
  app reference. Delete them or make them internal.
- **Leftover directory.** `Packages/PlinxTestSupport` contains only an empty
  `Sources` folder.

### Later: module boundaries

Once the first feature reviews are done, move `Strimr/Shared` into a local
Swift package with targets for models, providers, safety, and features, using
`package` access instead of `public`. The app target then depends only on the
safety target's services, so unfiltered content is unreachable by construction,
not just by convention. Do this after cherry-picking from upstream has stopped
paying off, because it changes every path.

## Phases

The durations are estimates, not commitments.

| Phase | Scope | Exit criteria | Estimate |
|---|---|---|---|
| P0 | Decisions D1–D10 | Recorded in this document | days |
| P1 | Fork day | Builds and tests pass on both platforms; no collection strings in the archive | 2–4 days |
| P2 | Safety boundary, rating normalization, Seerr protocol, launcher coverage | Conformance test passes; live parity tests pass on Plex | 1–2 weeks |
| P3 | Merge shadows into originals: timeline, player chrome, detail actions, tvOS focus | No same-name overrides left; UI and focus tests pass | 1–2 weeks |
| P4 | Jellyfin onboarding and accounts | Kid flow works end to end on a Jellyfin server; live parity tests on Jellyfin | ~1 week |
| P5 | Seerr kid flow | Requests attributed to the kid's Seerr user; uncertified titles never shown | 1–2 weeks |
| P6 | Parent tools: Manage, settings consolidation | No Manage entry in kid mode (UI test); destructive actions need a PIN | ~1 week |
| P7 | Shrink pass | Items above closed or ticketed | ~1 week, then ongoing |
| P8 | Live TV allowlist, filtered Top Shelf, in-app approvals | Separate privacy and safety review | Later |

## Maintaining The Fork

- **Monthly feature review.** Run `git fetch strimr-upstream` and triage new
  commits into adopt, port, gate or reject, as in the
  [triage appendix](strimr-contributions/15-upstream-main-migration-plan.md).
  Port with `git cherry-pick -x -X subtree=Strimr` while paths still match;
  otherwise reimplement. Record the review date in `Strimr/UPSTREAM.md`.
- **Contribute back when it's cheap.** Send generic bug fixes upstream when
  that's easy, but nothing depends on upstream accepting them.
- **GPL-3.0.** Strimr is GPL-3.0, so the Plinx repository is now the
  corresponding source for every build. Keep `Strimr/LICENSE` and the
  notices. Update `docs/release/open-source-compliance.md`.
- **Keep the old fork available.** Archive `bballdavis/strimr` read-only and tag
  every Strimr commit that a shipped Plinx build used. Do not delete it: those
  commits are the corresponding source for past releases.
- **Update the rules in the fork-day change.** Replace the Strimr routing and
  upgrade-inventory rules in `AGENTS.md` with fork rules. Rewrite
  `docs/architecture/strimr-integration.md`. Retire
  `docs/development/branch-pairing.md`. Update `setup.md`, `ci.md`,
  `testing.md`, and the dependency loader.

## Acceptance Gates

These carry over from the July audit, extended to the new providers:

1. **Fail-closed filtering.** Applies to every provider (Plex, Jellyfin, Seerr)
   on iOS and tvOS, proven by the conformance test and live parity tests.
2. **No collection code.** The archive contains no Sentry, Trakt or Simkl code
   or strings, and the privacy manifest declares no collection.
3. **No external links or social actions in kid UI.** This covers trailers,
   Seerr links and SharePlay initiation.
4. **Parent-only tools stay gated.** The Manage menu, server writes and settings
   are reachable only through the parental gate.
5. **OS minimums.** iOS, iPadOS and tvOS 18, per D1.
