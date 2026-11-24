# Strimr Upstream Migration Plan — 2026-11

Audit date: 2026-11-23. This is a plan only. It does not change the Strimr pin,
the paired branch, or any remote. Follow
[branch pairing](../../development/branch-pairing.md) and the
[upstream audit](../strimr-upstream-audit-2026-07-25.md) when you carry it out.

> **Decision update, 2026-11-23:** Plinx will hard fork Strimr instead of
> keeping a paired sibling checkout. See the
> [hard-fork plan](../strimr-hard-fork-plan.md). This document remains the
> commit triage for that fork. Jellyfin, Seerr and the Manage menu are now
> adopted with Plinx safety work instead of excluded; the conflict table and
> appendix below reflect that. The cherry-pick and patch-reconciliation sections
> describe the paired model and apply only if the fork is deferred.

## Audited Revisions

These are snapshot values for this audit. The current pin is defined by
`config/release-dependencies.env` and shown on the
[current dependencies](../current-dependencies.mdx) page.

| State | Revision | Meaning |
|---|---|---|
| Plinx pin at audit time | `67fd7bb` | Same commit as the heads of `origin/dev-plinx` and `origin/plinx-patches`; 42 downstream commits on top of `e0a8cbc` |
| Upstream base | `e0a8cbc` (2026-07-26) | Upstream commit the downstream patches sit on |
| Audited upstream | `0235d27` (2026-11-21) | `upstream/main`: 282 commits, 948 files, +140,522 / −21,610 lines past the base |
| Last iOS 17-compatible upstream | `c827455` (2026-10-01, #191) | Last commit whose resolved AetherEngine supports iOS 16+ and tvOS 17+ |

## Recommendation

Moving to newer Strimr is worth doing after the current test build ships, but
it is a full migration, not a fast-forward or a batch of cherry-picks. Plan it
as a new pairing branch built on upstream. Do not rebase `dev-plinx` onto it.

- **Worth it:** upstream adds multi-version and edition playback,
  chapters, scrub thumbnails, skip segments, iPhone Duo support, a reworked
  offline store, many player and tvOS focus fixes, newer AetherEngine and
  FFmpeg builds with security fixes, and a unit-test target. Staying on `e0a8cbc`
  means drifting further from an upstream that moves quickly (about 70 commits a
  month).
- **Expensive:** upstream added a provider layer (Jellyfin, #148), multi-server
  sessions (#200), a `MediaIdentity` download model (#155), a design-system
  refresh (#256), two full reformats, and tvOS type and file renames (#142).
  Almost every downstream patch and every Plinx type override needs to be
  replayed or rebuilt. Of the 25 cherry-picks tried onto the pin, only five
  applied cleanly (#113, #150, #198, #233, #234).
- **Blocked on a product decision:** upstream raised iOS to 18 (#192, from
  `0a06c04` onward), and the AetherEngine revision upstream resolves now
  declares iOS 18 and tvOS 18 as its minimum. Plinx's acceptance gate is iOS 17.5
  and tvOS 17. Plinx cannot reach current upstream without raising both minimums,
  or without pinning an older AetherEngine that current Strimr sources may no
  longer compile against.

The four acceptance gates from the July audit still apply: fail-closed safety
filtering, no collection code in the binary, social and external actions hidden
from kid-facing UI, and the approved OS minimums.

## Decisions Required Before Starting

1. **OS minimums.** Choose one of these options:
   - **Raise the minimums.** Move Plinx to iOS 18 and tvOS 18 and target
     `upstream/main`. Recommended if analytics-free install-base data or App
     Store Connect device data shows few iOS 17 or tvOS 17 families.
   - **Stop at `c827455`.** Hold Plinx at iOS 17.5 and tvOS 17. This takes 93 of
     the 282 commits and still includes the Jellyfin, `MediaIdentity` and offline
     rewrites. It loses everything after October 1 and leaves Plinx on a dead
     end.
   - **Defer the migration.** Stay on the current pin and backport only the
     clean fixes listed below.
2. **Xcode version.** Upstream CI moved to Xcode 27 (#201) and fixes iOS 27
   crashes (#212). Plan to raise Plinx from Xcode 26.5 in the same change.
3. **New third-party code.** Upstream adds the `GRDB` (offline store) and
   `wunax/swift-ass-renderer` (ASS subtitles) packages, and changes the
   AetherEngine feature traits (DTS:X, TrueHD and Dolby Vision object audio are
   opt-in traits, and LibDTSX was dropped). Each needs a license and notice
   review under [open-source compliance](../../release/open-source-compliance.md)
   and a privacy manifest check.

## Policy Conflicts

These upstream features conflict with `AGENTS.md`
or [privacy and safety](../../security/privacy-and-safety.md). Because Plinx
compiles all of `Shared/`, each one must be **excluded from the binary or replaced
with a Plinx stub**. Hiding the entry point alone is not enough.

| Upstream feature | PRs | Conflict | Required Plinx handling |
|---|---|---|---|
| Trakt and Simkl scrobbling | #384, #395, `f8cd117`, `436735c` | Sends viewing history to third parties, which breaks zero collection | Exclude `Shared/Trackers/**`. `SessionManager`, `PlayerViewModel`, `MediaQuickActions` and the offline progress code reference it, so add Plinx no-op stubs, as done for `ErrorReporter`. Add a binary string check for `api.trakt.tv` and `simkl` to archive validation |
| Sentry additions | #172, #232, #247 | Collection | Already neutralized by the no-op `ErrorReporter`. Keep the `Monitoring/ErrorReporter.swift` exclude and confirm `sentry-cocoa` stays out of the resolved graph |
| External player hand-off | #228 | Policy forbids handing playback to another app because it bypasses content checks and the volume cap | Exclude `ExternalPlayerApps.swift` and `ExternalPlaybackCallbackHandling.swift`, or stub them so no player is ever listed. Add a test that no external player option renders |
| Seerr trailers on the web or YouTube | #343, #350 | External links in kid-facing UI | Hide trailer buttons in kid UI. Parent-only surfaces may link out |
| Seerr request flows | #235, #262, #359, #410–#412 | Unfiltered discovery of arbitrary catalog content | Adopt with a per-kid Seerr user, certification filtering that fails closed, and parent approval. See the hard-fork plan |
| Server Manage menu | #337, #340, #342, #345, #346, #348, #349, and #268's write actions | Destructive server-admin actions (delete media, empty trash, edit metadata, upload artwork). The account Plinx signs in with is often the server owner | Parent-only: entries render only while the parental gate is unlocked. Destructive actions need a fresh PIN and confirmation. Add tests that no Manage entry renders in kid mode on either platform |
| Live TV and DVR | #165, #254, #372, #393, #422 | Programs have no per-item rating Plinx can enforce, so filtering cannot fail closed | Exclude Live TV navigation. Keep the tab and home rows hidden |
| tvOS Top Shelf with progress | #394 (plus the July Top Shelf decision) | Shows viewing history and artwork outside the gated UI | Keep the Top Shelf extension out of Plinx |
| Jellyfin | #148 and later Jellyfin fixes | Plinx safety adapters cover Plex only | Adopt. Add Jellyfin onboarding, normalize Jellyfin ratings, and filter all providers at one services boundary |
| iOS 18 minimum | #192 | Breaks the approved iOS 17.5 and tvOS 17 minimums | Product decision above |

These features need a **parental gate, a Plinx filter seam, or the sanitizer**
before kid-facing use.

| Feature | PRs | Handling |
|---|---|---|
| New content sources: person filmography, extras and trailers, folder tree, items shared one at a time, arbitrary library hubs on home, featured hero carousel | #121, #174, #202, #328, #237, #365 | Extend [library filtering seams](02-library-filtering-seams.md) to each new view model, or exclude the surface. Unrated extras are rejected by default, but only if the filter is applied |
| Autoplay, queue, play from Continue Watching, downloaded-copy fallback | #159, #160, #313, #324, #392 | Every playback entry point must go through `PlinxPlaybackLauncher`. Add tests for autoplay of the next episode when its rating exceeds the cap |
| Server write actions: favorites, playlists, remove from Continue Watching, subtitle search and auto-apply | #161, #257, #336, #133, #138, #374, #376 | Hide in kid UI. Subtitle search can be offered behind the parental gate |
| Profile re-prompt after 15 minutes, profile picker refresh | #419, #227 | The re-prompt could offer adult profiles to a child. Disable it in Plinx or route it through `ParentalAccessCoordinator` |
| Picture in Picture and background audio | #145, #367 | Parent-only settings, off by default |
| Downloads before sign-in, offline mode | #154, #186 | Keep `DownloadOwnershipStore` scoping. Downloads from another server or profile must not appear before sign-in |
| tvOS system player style | #413 | Force the Plinx custom player, which keeps Plinx chrome, the timeline, and hidden controls. Hide the setting |
| Default playback speed | #334 | Plinx removed speed control. Hide the setting and pin speed to 1× in the sanitizer |
| About, licenses, privacy page with external links | #263 | Parent-only. Reuse the license list for Plinx's compliance surface |
| Settings surfaces: home rows, library visibility page, cellular override, custom server URL | #181, #352, #180, #157 | Keep them behind the parental gate. Plinx owns library visibility |
| Screenshot demo mode | #272 | Must not be reachable. Plinx has its own loopback demo |

## Cherry-Pick Shortlist For `dev-plinx`

Each candidate was cherry-picked onto `67fd7bb` in a throwaway detached worktree,
then compared with the downstream patches and `STRIMR_REQUIRED_SEAMS`.

### Requested candidates

None of the suggested fixes can be cherry-picked onto the pin:

| Candidate | Result on the pin | Verdict |
|---|---|---|
| #421 download retry | Conflicts in `DownloadManager`, download rows, both download views, and localization. Depends on `MediaIdentity` (#155), per-server services (#200), `ownerID`, and version-aware preparation (#190) | **Do not backport.** The rejection of HTTP error bodies is already covered, more strictly, by downstream patch 07 (`DownloadIntegrityValidator` checks status, MIME type, empty file, and `Content-Length`/`Content-Range`). Take retry-with-resume-data with the full migration and keep the Plinx validator in the new `didFinishDownloadingTo` path |
| #398 subtitle score decoding | Conflicts. The pin has no subtitle search | Not applicable |
| #399 lenient Plex decoding | Conflicts. Depends on `PlexLenientDecoding` from #232 | Take with the migration. It replaces [flexible boolean decoding](03-flexible-plex-boolean-decoding.md): the `PlexFlexibleBool` seam token becomes `PlexLenient`. Lossy arrays drop malformed items, which fails closed, and unrated items stay rejected because `allowUnrated` defaults to false |
| #400 Jellyfin wrapped lists | Conflicts. Jellyfin only | Not applicable |
| #404 library scroll re-render | Conflicts. Fixes code from #356 that the pin doesn't have | Not applicable |
| #409 tvOS home row scrolling | Conflicts. The pin's `MediaCard` already draws no shadow when unfocused, and `cardFocusCount` arrives later | Not applicable |
| #416 tvOS library grid scrolling | Content conflicts with downstream compact pagination (patch 02) | Take with the migration and replay `itemFilter` and compact pagination on the new `LibraryBrowsePageTracker`. A backport is possible only if Plinx tvOS grid jank shows up in profiling |
| #406 episode list freeze | Conflicts. The pin has no `rowWidth` measurement, so the bug arrived later | Not applicable |
| #402 rotation after background | Conflicts. Fixes #250 auto-rotation, which the pin doesn't have | Not applicable |

### Clean, low-risk backports

These apply cleanly to `67fd7bb`, touch no seam token, and fix behavior that
exists at the pin. They are small enough to take on `dev-plinx` after the test
build ships.

| PR | Commit | Change | Notes |
|---|---|---|---|
| #233 | `7eaa318` | Clamp Plex timeline `time` to `duration` | Avoids HTTP 400 progress reports at the end of playback |
| #234 | `1068437` | Skip watchlist lookup for non-`plex://` guids | Fewer failing requests for legacy-agent libraries |
| #150 | `ef7e03a` | Episode artwork in Continue Watching | Visual only |
| #198 | `1adf264` | Reset the tvOS scroll view per library folder level | Touches the tvOS `LibraryBrowseViewModel`, which carries the `itemFilter` seam. Additive only, but run tvOS filtered pagination tests |
| #113 | `1541496` | Tolerate Plex streams without IDs | Makes `PlexStream.id` optional. Build Plinx adapters and player views before taking it |

Port by hand if wanted: **#137** (`16d8709`, concurrent connection probing). It
conflicts only around the `operationSnapshot()` seam in `PlexAPIContext` and
noticeably speeds up server selection. **#249** (`ea5d1cc`, ignore 404 when
stopping an ended transcode) conflicts in one file.

Every backport is a Strimr-side edit. Record it in the upgrade inventory and
run the full integration contract before moving the pin.

## Player Timeline Interaction

Plinx excludes Strimr's `Shared/Features/Player/Controls/PlayerTimelineView.swift`
on both platforms. It supplies `PlinxApp/Views/Player/PlinxPlayerTimelineView.swift`,
which declares a type of the same name and relies on matching Strimr's public
shape. That contract breaks during the migration.

- At the pin, the shadowed shape is `position`, `duration`, `bufferedAhead`,
  `playbackPosition`, and `onEditingChanged`.
- At `upstream/main`, the timeline also takes `playbackRate`,
  `showsEndsAtTime`, `chapters`, `showsChaptersOnTimeline`, `skipSegments`,
  `scrubPreview`, `floatsScrubDetails`, `onCancel`, `swipesScrub`, and
  `onIdleSwipe`. These come from #117 chapters, #119 scrub thumbnails, #120
  and #122 end time, #316 skip segments, and the tvOS scrub rework.
- Upstream callers are the iOS `PlayerControlsView`, `PlayerTabletopControlsView`
  (iPhone Duo, #260), and the tvOS `PlayerControlsView`.
  `PlayerTimelineScrubberView` and `PlayerChapterViews` (`PlayerChapterTimeline`)
  also take `skipSegments`. The tvOS system player style (#413) uses its own
  `SystemPlayerTimelineView`.

Plan:

1. Extend the Plinx timeline to accept the full upstream parameter list, with the
   same defaults, so upstream callers compile unchanged. Unused parameters must
   be accepted, not removed.
2. **Skip segments (#316).** Upstream draws segments only when
   `showSkipSegmentsOnTimeline` is on (default off) and passes `[]` otherwise.
   Accept `skipSegments` and leave them unrendered in the first migration. A
   later Plinx design can draw them as tinted spans along the raised curve. They
   come from `viewModel.markers` (intro, credits, commercials), so they carry no
   safety risk. Keep the setting hidden until Plinx renders segments.
3. **Chapters and scrub thumbnails.** Scrub previews are BIF images of the same
   authorized item. They are acceptable, but they must fit above the raised hump
   without collapsing the handle-first touch target. Chapter ticks need the same
   design pass.
4. **tvOS input.** Upstream moved tvOS scrubbing into the timeline
   (`onCancel`, `swipesScrub`, `onIdleSwipe`, `PlayerScrubInteraction`).
   Reconcile these with Plinx remote and focus handling and the
   `PlayerTimelineEditingLifecycle`. Rerun the tvOS remote walk tests and
   `PlayerTimelineUITests`.
5. Add the iPhone Duo tabletop caller to the layout and snapshot checks.
6. Update `PlayerTimelineTests` for the new parameters, and the
   `PlayerTimelineUITestHarness` for renamed tvOS types.

## Downstream Patch Reconciliation

Every downstream commit at the pin must end the migration as **adopted**
(upstream now does it), **dropped**, **kept in Plinx** (moved to a Plinx layer),
or **replayed** (reapplied in Strimr and recorded here).

| Downstream commits | Plan | Expected disposition | Upstream overlap |
|---|---|---|---|
| `3ffa298` SharePlay presentation policy | [10](10-shareplay-presentation-capability.md) | Replay | No upstream equivalent found |
| `bc3fdca`, `1edd9fe` filter, clip, search and logo seams | [01](01-plex-clip-media-support.md), [02](02-library-filtering-seams.md), [04](04-ios-clear-title-logos.md), [06](06-search-visibility-parity.md) | 01: partly adopted (`clip` came with #174; check Other Videos libraries). 02, 04, 06: replay | View models were reworked by #148, #194–#202, #356, #360, and #416. Search moved to multi-server (#139, #327) |
| `8d9412a`, `24d9689` playback authorization, volume cap, quick sort | — | Replay seams, keep policy in Plinx | Player files renamed (#142) and heavily changed |
| `513e3e0`, `75052bd` offline progress and local playback state | [08](08-offline-playback-progress.md) | Probably adopted. Check against `OfflineCoordinator` and `ProgressSynchronizer` (#186), then drop | #186, #305 |
| `e44aed0` offline artwork layout | — | Keep in Plinx | — |
| `10bc877`, `36fc2ee` optimistic watched status | — | Replay or move to Plinx | #158, #299, #312 changed watch actions |
| `7e4d78b`, `1ef6a7b` download index and integrity | [07](07-download-integrity-and-index-recovery.md) | Replay the validator and index recovery on the `MediaIdentity` download manager | #155, #315, #421 (partial overlap) |
| `225f7e3` download network lifecycle | — | Keep in Plinx where possible, otherwise replay | #180, #421 |
| `0ecbfb1` download quality settings | [11](11-download-queue-transcoding.md) | Mostly adopted (#164 transcoding downloads). Drop the quality enums, replay only the 20% space-savings guard | `DownloadQueueRepository` upstream |
| `bd1242c` session bootstrap seams | — | Replay against the multi-server `SessionManager` and `ServerRegistry` | #200, #208, #218 |
| `c0ace87` explicit server preference | [09](09-explicit-default-server-preference.md) | Recheck. Multi-server (#200) may make it unnecessary | #200 |
| `22d929c` recently-added variants | [05](05-recently-added-hub-classification.md) (retired) | Recheck against the new home and featured aggregation | #321, #365 |
| `9cf6cf0` buffering overlay seam | — | Replay on the renamed tvOS `PlayerWrapper` and `PlayerView` | #124, #142 |
| `b8eb163`–`3f29386` (11 commits) media detail action chrome, glyphs, labels | — | Move into a Plinx override if possible, otherwise replay | #129, #135, #256 design system |
| `496caa0` host-app Plex identity | [12](12-plex-authentication-product-identity.md) | Replay | Upstream still hard-codes `Strimr` in `PlexCloudNetworkClient`, `PlexServerNetworkClient`, and the new `PlexLiveTVQuery` |
| `b8cbf9b`, `42ec700`, `66842d4` season download picker | [13](13-season-download-selection.md) | Replay on `MediaIdentity` | #155, #190 |
| `45e3113` download enrollment and scoping | [13](13-download-enrollment-and-access-scoping.md) | Replay the enrollment callback. Compare with upstream `ownerID` | Upstream added per-user `ownerID` |
| `67fd7bb` title interaction lifetime | [14](14-player-title-interaction-lifetime.md) | Replay | #291 episode title in the player header, #370 split settings |
| `c2b3df0`, `b2f72f3`, `f3a4d47`, `78eb81e`, `77cd287`, `3b5f30c` target scoping | — | Redo in `PlinxApp/project.yml` | #330 adds `Shared` to the tvOS target |
| `dadb44a`, `c0ac36c`, `657d5c2` localization | — | Regenerate after merging | `17374fe` and later string changes |
| `aaae19b`, `e66a77d`, `66842d4`, `3f29386` formatting and promotion | — | Drop. Reformat with upstream SwiftFormat 0.64.5 | #255, #331 |

### Seam and project changes

- **Renamed tvOS files (#142).** Update `STRIMR_REQUIRED_SEAMS`:
  - `PlayerTVView.swift` becomes `PlayerView.swift`
  - `PlayerTVWrapper.swift` becomes `PlayerWrapper.swift`
  - `Controls/PlayerControlsTVView.swift` becomes `Controls/PlayerControlsView.swift`

  Also update the tvOS excludes in `project.yml`: `Auth/SignInTVView.swift` is now
  `Auth/SignInView.swift`, and `Player/Controls/PlayerControlButtonsTV.swift` is
  now `PlayerControlButtons.swift`. Plinx code that names `PlayerTVView`,
  `PlayerControlsTVView`, or `SignInTVView` must follow the renames.
- **Seam tokens already upstream.** `PlayerControlsView(`, `PlayerSettingButton(`,
  `SkipMarkerButton(`, and `PlayerTrackSelectionView(`.
- **Tokens to rewrite.** `PlexFlexibleBool` becomes `PlexLenient`. The
  download-quality tokens follow the plan 11 disposition.
- **Every other token** must be replayed.
- **Plinx type overrides to rebuild against the new shapes.** iOS
  `PlayerControlsView` and `PlayerControlButtons`; tvOS `PlayerControlButtons`
  and `PlayerTrackSelectionView`; tvOS paged library view models; the timeline;
  the playback launcher; `MediaRatingLabel`; `MediaBackdropGradient`.

## Migration Stages

1. **Ship the current test build.** Optionally take the five clean backports on
   `dev-plinx` and record them.
2. **Decide** the OS minimums, Xcode version, and new dependency licenses.
3. **Spike.** Create a Strimr branch from the chosen upstream commit. Replay only
   the seams, then generate the Plinx project and collect compiler diagnostics on
   iOS and tvOS. Expect about 1–2 weeks of compatibility work before features are
   tested, based on the size of the July migration and the number of overrides.
4. **Neutralize** Trackers, external player, Manage, Live TV, Seerr links, and
   Top Shelf, with tests and binary string checks.
5. **Close the safety gaps.** Add filter seams for the new content sources and
   launcher coverage for autoplay and queue paths. Run live parity tests.
6. **Rebuild Plinx UI overrides:** timeline, player chrome, media detail actions,
   and tvOS focus.
7. **Validate:** playback matrix, offline, downloads ownership, archive privacy
   validation, and `./scripts/verify_strimr_integration_contract.sh --full`.
8. **Close the inventory.** Every patch in the table above must be marked adopted,
   dropped, kept, or replayed. Push the paired Strimr commit, then change the pin.

## Upstream Commit Triage

Dispositions:

- **A:** adopt with the baseline.
- **A\*:** adopt, but it touches a Plinx seam, override, or downstream patch and
  needs replay or verification.
- **C:** clean backport candidate for `dev-plinx`.
- **G:** must be gated, filtered, or hidden in Plinx.
- **R:** reject for Plinx; exclude or stub it so it is unreachable.
- **N:** not applicable (CI, docs, versions, formatting, macOS-only,
  Jellyfin-only, or Seerr-only while Seerr is disabled).

Totals for the 282 commits: A 139, A\* 36, C 6, G 37, R 13, N 51. The C total
includes #137, which needs a hand port.

| Date | Commit | Change | Disp. | Plinx note |
|---|---|---|---|---|
| 2026-07-27 | `1541496` | fix: tolerate Plex streams without IDs (#113) | C | Applies cleanly; `PlexStream.id` becomes optional, so Plinx adapters must compile against it |
| 2026-07-27 | `848ee57` | chore: update packages revisions | N | Package revisions |
| 2026-07-28 | `003f222` | feat: plex chapter navigation (#117) | A\* | Chapters feed the timeline contract Plinx shadows |
| 2026-07-30 | `03ce0f9` | feat: scrubbing thumbnails (#119) | A\* | Scrub thumbnails add `scrubPreview` to the shadowed timeline |
| 2026-07-30 | `62668da` | chore: ignore build folder in swiftformat | N | Tooling |
| 2026-07-30 | `2a22c26` | feat: add configurable player end time (#120) | A\* | End time adds timeline parameters |
| 2026-07-30 | `ef4a267` | feat: add Plex person detail view (#121) | G | Person filmography is a new content source; needs `itemFilter` |
| 2026-07-31 | `ed2261c` | ui: refine player end time placement (#122) | A\* | Timeline layout |
| 2026-07-31 | `90b32e2` | feat: add optional tvOS player clock (#123) | A | Optional clock |
| 2026-07-31 | `be0bb27` | feat: loading progress (#124) | A | Loading progress |
| 2026-07-31 | `83c5b26` | ui: keep subtitles above playback controls (#125) | A | Subtitle placement |
| 2026-08-01 | `003350f` | fix: recover Plex authorization during playback (#126) | A | Auth recovery during playback; conflicts with player overrides, take with baseline |
| 2026-08-01 | `fd5eb93` | feat(tvOS): episode actions (#127) | A\* | tvOS episode actions; check that watched-state writes match Plinx quick actions |
| 2026-08-01 | `2170b5f` | fix: align player timeline time labels | N | Strimr timeline file is excluded by Plinx |
| 2026-08-01 | `59c4ea2` | feat: ass subtitle rendering (#128) | A | ASS rendering; adds `swift-ass-renderer`, needs a license review |
| 2026-08-01 | `57238a0` | ui(tvOS): consolidate tvOS media actions (#129) | A\* | tvOS media actions are consolidated; Plinx action chrome patches must be replayed |
| 2026-08-01 | `e8b3a94` | feat: media track selection (#130) | A | Track selection |
| 2026-08-02 | `216dae5` | feat: add episode spoiler protection (#131) | A | Spoiler protection |
| 2026-08-02 | `ce53871` | feat: support Plex external subtitles (#132) | A | Plex external subtitles |
| 2026-08-02 | `aae7910` | feat: external subtitle search (#133) | G | Subtitle search writes the subtitle to the server; parent-only |
| 2026-08-03 | `bba377c` | feat: add automatic intro and credits skipping (#134) | A | Auto skip intro and credits; default off |
| 2026-08-03 | `28974a2` | chore: update packages revisions | N | Package revisions |
| 2026-08-03 | `2bf2df8` | ui: increase macOS default window size | N | macOS |
| 2026-08-04 | `c5cb600` | chore: update packages revisions | N | Package revisions |
| 2026-08-04 | `ce0333b` | ui: media detail alignment (#135) | A | Detail alignment |
| 2026-08-04 | `78d4f03` | feat: overlay tvOS library sidebar (#136) | A\* | tvOS library sidebar overlay; recheck Plinx focus treatment |
| 2026-08-04 | `32672b5` | chore: update packages revisions | N | Package revisions |
| 2026-08-04 | `16d8709` | fix: resolve Plex connections concurrently (#137) | C | Faster connection selection; hand-port around the `operationSnapshot()` seam |
| 2026-08-05 | `1025967` | ci: support macOS in version bump workflow | N | CI |
| 2026-08-05 | `e0e8bf9` | ci: scope TestFlight build numbers to current version | N | CI |
| 2026-08-05 | `50c155b` | feat: enable tvos subtitle search (#138) | G | tvOS subtitle search; parent-only, as with #133 |
| 2026-08-05 | `6b22bc4` | docs: update key features | N | Docs |
| 2026-08-08 | `d3dc54a` | feat: multi servers search (#139) | A\* | Multi-server search; downstream patch 06 (hidden-library parity) must be replayed on the new search path |
| 2026-08-08 | `114d8f7` | chore: bump version to 1.2.1 (#140) | N | Version |
| 2026-08-08 | `b74e2b3` | ci: preserve shared TestFlight build numbers | N | CI |
| 2026-08-08 | `b31b8ff` | ci: allow custom TestFlight build number | N | CI |
| 2026-08-09 | `17374fe` | chore: remove unused translations | A\* | Localization pruning; replay Plinx strings |
| 2026-08-09 | `1506437` | refactor: standardize platform-specific naming (#142) | A\* | tvOS type and file renames break Plinx excludes, seams, and type references |
| 2026-08-09 | `581b22c` | chore: update project.pbxproj | N | Project file |
| 2026-08-12 | `11e9cd9` | docs: refresh platform screenshots | N | Docs |
| 2026-08-12 | `ac39a1e` | docs: refresh README branding (#143) | N | Docs |
| 2026-08-12 | `81e80a8` | docs: update contributing guide (#144) | N | Docs |
| 2026-08-13 | `6e15f17` | fix: preserve rotation control localization keys | A | Localization keys |
| 2026-08-13 | `79defbf` | chore: bump packages revisions | N | Package revisions |
| 2026-08-13 | `8e116d4` | style: format code | N | Formatting |
| 2026-08-13 | `6eecded` | feat: add picture in picture playback (#145) | G | Picture in Picture keeps video outside the app; parent-only setting, default off |
| 2026-08-14 | `1b55398` | ci: add macOS build check | N | CI |
| 2026-08-14 | `e9b3561` | chore: remove unused Watch Together server | N | Watch Together server removal |
| 2026-08-14 | `366bc70` | ci: parallelize platform builds | N | CI |
| 2026-08-14 | `daf1652` | fix: allow omitted TestFlight build number | N | CI |
| 2026-08-14 | `de60073` | chore: update fastlane plugins | N | Fastlane |
| 2026-08-14 | `a63ddad` | feat: add reliable macOS player fullscreen (#146) | N | macOS |
| 2026-08-17 | `68f27ed` | chore: bump version to 1.3.0 (#149) | N | Version |
| 2026-08-18 | `91c1538` | feat: jellyfin support (#148) | A\* | Jellyfin provider layer: adopt. Needs Plinx onboarding, rating normalization, and the safe services boundary |
| 2026-08-18 | `ef7e03a` | fix: show episode artwork in continue watching (#150) | C | Applies cleanly; Continue Watching episode artwork |
| 2026-08-18 | `1d5ab97` | fix: isolate player sheet presentation (#151) | A | Player sheet isolation |
| 2026-08-18 | `16424c1` | fix: keep tvOS player open when dismissing chapters (#152) | A | tvOS chapters fix |
| 2026-08-18 | `4dc124a` | ui: improve missing artwork placeholders (#153) | A | Artwork placeholders |
| 2026-08-19 | `4e3b542` | feat: expose downloads from authentication screens (#154) | G | Downloads before sign-in bypass profile ownership scoping |
| 2026-08-19 | `29c7ab5` | refactor: update download management to use MediaIdentity  (#155) | A\* | `MediaIdentity` download refactor; patches 07, 08, 11 and 13 must be rebuilt on it |
| 2026-08-20 | `d5b8910` | refactor(iOS): use legacy tabview for ios 17 support (#156) | N | Legacy tab view; superseded by #192, and Plinx owns its tabs |
| 2026-08-20 | `e936c50` | feat: custom url plex server (#157) | G | Custom server URL; parent-only |
| 2026-08-21 | `17b8500` | fix: media detail watch actions (#158) | A\* | Media detail watch actions; check Plinx quick actions |
| 2026-08-21 | `00285d7` | feat: post play autoplay (#159) | G | Autoplay must route every next item through Plinx playback authorization |
| 2026-08-21 | `40dc5e0` | feat: player queue view (#160) | A\* | Queue view; check that the launcher filters every queue member |
| 2026-08-22 | `5b942b4` | feat: add Jellyfin and Plex favorites (#161) | G | Favorites write to the server account; hide in kid UI |
| 2026-08-22 | `911fa54` | feat: add downloads tab visibility setting (#162) | A | Downloads tab visibility |
| 2026-08-22 | `88cf0f8` | refactor: remove redundant Jellyfin genres tab | A | Jellyfin |
| 2026-08-22 | `efeaf30` | feat: add playback quality transcoding (#163) | A | Playback quality transcoding |
| 2026-08-23 | `83a3e7c` | feat: transcoding downloads (#164) | A\* | Transcoding downloads replace most of patch 11; keep the 20% space-savings guard |
| 2026-08-26 | `ee3ea6c` | feat: live tv (#165) | R | Live TV programs carry no per-item ratings Plinx can enforce; exclude |
| 2026-09-01 | `d2b2f38` | fix: swift optimizer deinit (#170) | A | Optimizer deinit crash |
| 2026-09-01 | `a8778a7` | docs: add Jellyfin info banner | N | Docs |
| 2026-09-01 | `2569b82` | style: format code | N | Formatting |
| 2026-09-14 | `1fa30c5` | chore: update packages | N | Package revisions |
| 2026-09-14 | `f398c5a` | fix: preserve selected tracks after background resume (#171) | A | Track selection kept on resume; conflicts with player overrides |
| 2026-09-14 | `be45f1b` | style: format code | N | Formatting |
| 2026-09-14 | `2e8e4d8` | fix: stabilize Live TV Sentry errors (#172) | R | Live TV and Sentry; both excluded |
| 2026-09-16 | `4a57693` | ui: customize library tab picker (#173) | A | Library tab picker |
| 2026-09-16 | `c751f94` | feat: plex jellyfin extras (#174) | G | Extras and trailers are new content sources; need a filter seam |
| 2026-09-16 | `855902e` | feat: remember track selections across episodes (#175) | A | Remember tracks |
| 2026-09-21 | `98f1b24` | feat: media file info (#176) | A | Media file info |
| 2026-09-23 | `459dcad` | feat: expand tvOS subtitle font size range (#179) | A | tvOS subtitle size |
| 2026-09-23 | `d5e57d4` | feat: cellular download override (#180) | G | Cellular override; parent-only setting |
| 2026-09-24 | `070344e` | feat: home row customization (#181) | G | Home row customization; settings stay behind the parental gate |
| 2026-09-25 | `087076e` | ui(tvOS): improve tvos presentation (#182) | A\* | tvOS presentation; recheck Plinx focus treatment |
| 2026-09-28 | `03ec2ad` | ui(tvos): settings split (#183) | G | tvOS settings split; Plinx owns gated settings |
| 2026-10-01 | `5731949` | feat: offline mode (#186) | A\* | Offline mode; must keep `DownloadOwnershipStore` scoping. Overlaps patch 08 |
| 2026-10-01 | `d823169` | fix(tvOS): artwork stuck empty after cancelled image load (#187) | A | Artwork after cancelled load; pin lacks the file |
| 2026-10-01 | `d9f317e` | fix(tvOS): home row visibility icon reflects state (#188) | A | Home row icon |
| 2026-10-01 | `a1aa098` | chore: add unit test target with Swift Testing (#189) | A | Unit test target |
| 2026-10-01 | `5e37849` | feat: multi version (#190) | A | Multiple versions |
| 2026-10-01 | `c827455` | ui(tvos): clearer quality icon and version/quality separation (#191) | A | Last commit whose AetherEngine supports iOS 17.5 and tvOS 17 |
| 2026-10-03 | `0a06c04` | chore: raise iOS minimum to 18 for AetherEngine  (#192) | R | Raises iOS to 18; AetherEngine now needs iOS 18 and tvOS 18. Needs a product decision |
| 2026-10-03 | `72443d2` | fix(player): render styled text subtitle cues (#193) | A | Styled subtitle cues |
| 2026-10-04 | `0914ef5` | feat: remember library browse sort and filters per library (#194) | A | Remember sort and filter |
| 2026-10-04 | `a4e46a9` | chore: run macOS tests in CI (#195) | N | CI |
| 2026-10-04 | `7e97a5a` | feat: add library list view and item count (#196) | A | List view |
| 2026-10-04 | `9780f4b` | feat: library display defaults (#197) | A | Display defaults |
| 2026-10-04 | `1adf264` | fix(tvOS): blank page when entering a library folder (#198) | C | Applies cleanly; tvOS folder scroll reset |
| 2026-10-04 | `7fd15bd` | feat: cumulative seek feedback (#199) | A | Seek feedback |
| 2026-10-05 | `db4651b` | chore: run CI on Xcode 27 (#201) | N | CI on Xcode 27; expect a Plinx Xcode bump |
| 2026-10-05 | `cd55e07` | feat: multi server (#200) | A\* | Multi-server; safety decorators must wrap every server's services |
| 2026-10-05 | `6519c9a` | feat: optional folder tree view for library folders (#202) | G | Folder tree is a new browse path; needs `itemFilter` |
| 2026-10-05 | `dd2222e` | feat: audio subtitle sync (#203) | A | Audio sync |
| 2026-10-05 | `327b3eb` | docs: mention multi-server in README key features (#204) | N | Docs |
| 2026-10-06 | `f1d1289` | fix: apply persisted folder tree on library load (#205) | A | Folder tree fix |
| 2026-10-06 | `d7744e0` | feat: sleep timer (#206) | A | Sleep timer |
| 2026-10-06 | `9eaa1c6` | feat: player media info (#207) | A | Player media info |
| 2026-10-06 | `86c2bf4` | fix: stale server connection after network change (#208) | A | Network change fix; conflicts, take with baseline |
| 2026-10-06 | `48340dc` | fix: respect spoiler protection in player media info (#209) | A | Spoiler fix |
| 2026-10-06 | `9c135ab` | feat: pause screen (#210) | A | Pause screen |
| 2026-10-07 | `ad20235` | fix: constrain ASS subtitles to video rect (#211) | A | ASS fix |
| 2026-10-08 | `1ec98ba` | fix(iOS): ios27 tab bar crash (#212) | N | Fixes `MainTabView`, which Plinx excludes; confirm Plinx tabs on iOS 27 |
| 2026-10-08 | `1899c6a` | fix: reorder libraries with arrows on every platform (#213) | A | Library reorder |
| 2026-10-08 | `aef810b` | fix: audio offset settings row truncation and move it to audio settings (#214) | A | Audio offset row |
| 2026-10-08 | `a04149c` | ui: group tab toggles in interface settings (#215) | A | Settings grouping |
| 2026-10-09 | `b24a666` | fix: remove Plex and Jellyfin logos for App Store review (#216) | A | Store review logo removal; check Plinx assets for the same issue |
| 2026-10-10 | `472b578` | fix: avoid out-of-range crash in ratings ForEach (#217) | A | Ratings crash |
| 2026-10-11 | `c9710b5` | fix: remove version settings from test target to unblock version bump (#219) | N | Tests |
| 2026-10-11 | `3ea7435` | chore: bump version to 1.3.1 (#220) | N | Version |
| 2026-10-11 | `b8715a0` | fix: drop revoked Plex session instead of blocking the migration (#218) | A | Revoked session migration |
| 2026-10-12 | `339706d` | chore: bump version to 1.3.2 (#221) | N | Version |
| 2026-10-13 | `8854930` | docs: remove Jellyfin TestFlight-only note from README (#222) | N | Docs |
| 2026-10-13 | `c1547cb` | docs: update README key features (#224) | N | Docs |
| 2026-10-13 | `be55739` | perf: decode off main actor (#223) | A | Off-main decoding |
| 2026-10-14 | `98bdc60` | ui: refresh tvOS player settings panel (#225) | A\* | tvOS player settings; recheck Plinx player chrome |
| 2026-10-14 | `9954c70` | fix(tvOS): browse content pushing library sidebar off-screen (#226) | A | tvOS sidebar fix |
| 2026-10-14 | `678fb47` | ui: profile picker refresh (#227) | G | Profile picker; profile switching must stay parent-gated |
| 2026-10-16 | `c6b1e1f` | feat: add external player support (#228) | R | External player hand-off is prohibited by policy; exclude `ExternalPlayerApps` |
| 2026-10-16 | `2412a18` | feat: play Plex theme music on detail pages (#229) | A | Theme music; detail pages are already authorized |
| 2026-10-18 | `e916a88` | feat: add Atmos and DTS:X spatial audio setting (#230) | A | Spatial audio |
| 2026-10-19 | `4fd1d98` | fix: tolerate malformed Plex items and report decoding failures (#232) | A\* | Lenient decoding replaces patch 03; unrated items stay rejected by policy |
| 2026-10-19 | `7eaa318` | fix: clamp Plex timeline time to duration (#233) | C | Applies cleanly; clamps timeline time |
| 2026-10-19 | `1068437` | fix: skip Plex watchlist lookup for non-plex guids (#234) | C | Applies cleanly; skips watchlist lookups for non-Plex guids |
| 2026-10-19 | `2b7fdc9` | feat: let users add any Plex library hub to the home (#237) | G | Arbitrary library hubs on home; `hubFilter` must apply |
| 2026-10-19 | `a2b82ef` | fix: tolerate Plex DVR commercial and unknown marker types (#238) | A | Marker types |
| 2026-10-19 | `007f9d5` | feat: skip Plex DVR and Jellyfin commercials (#239) | A | Commercial skip |
| 2026-10-20 | `b11c1ed` | fix: fit bitmap subtitle canvas to screen (#240) | A | Bitmap subtitle fit |
| 2026-10-20 | `71af0ee` | fix: tvos server selection focus (#242) | A | tvOS focus |
| 2026-10-20 | `8150e9d` | feat: rework Seerr requests, ratings and collections (#235) | G | Seerr requests: adopt with per-kid Seerr user, certification filtering, and parent approval |
| 2026-10-20 | `77686ab` | feat: double tap to seek in iOS player (#243) | A | Double tap seek |
| 2026-10-20 | `3b98a20` | fix: tvos settings sidebar focus (#244) | A | tvOS focus |
| 2026-10-20 | `8ae522f` | fix: decode and cache Jellyfin artwork off the main thread (#245) | A | Jellyfin artwork decoding |
| 2026-10-20 | `847b501` | fix: dedupe Jellyfin libraries returned by UserViews (#246) | A | Jellyfin library dedupe |
| 2026-10-20 | `b8f708e` | fix: stop reporting unreachable hosts and automatic failed requests t… (#247) | A | Fewer reports; Plinx reporter is a no-op anyway |
| 2026-10-20 | `8447a15` | fix: back off Plex PIN polling when rate limited (#248) | A | PIN polling backoff; can replace Plinx's unproven backoff |
| 2026-10-20 | `ea5d1cc` | fix: ignore 404 when stopping an already ended Plex transcode (#249) | A | Transcode stop 404 |
| 2026-10-21 | `fd8d96a` | ui(tvOS): hero transitions (#252) | A\* | Hero transitions; recheck focus |
| 2026-10-22 | `0a0e56c` | fix: negotiate a client profile before starting Plex Live TV streams (#254) | R | Live TV |
| 2026-10-22 | `38f3b70` | chore: reformat with SwiftFormat 0.64.0 (#255) | N | Reformat; causes heavy textual conflicts |
| 2026-10-23 | `be98b80` | ui: refresh the app on a shared design system across iOS, macOS and tvOS (#256) | A\* | Design system refresh; largest UI conflict with Plinx chrome and PlinxUI |
| 2026-10-24 | `3157865` | feat: playlist management (#257) | G | Playlist management writes to the server; hide in kid UI |
| 2026-10-24 | `95e9c65` | fix: iphone duo layout (#258) | A | iPhone Duo layout |
| 2026-10-24 | `2cd0bf3` | fix: remove the iPhone Duo sidebar that crashes when folding during playback (#259) | A | iPhone Duo crash |
| 2026-10-25 | `437dd89` | feat: duo tabletop player (#260) | A | Duo tabletop player; adds another timeline caller |
| 2026-10-25 | `b5d75fa` | feat: add subtitle brightness setting and softer subtitle colors (#261) | A | Subtitle brightness |
| 2026-10-25 | `b4c480e` | ui: redesign Seerr request cards around the media backdrop (#262) | A | Seerr cards UI |
| 2026-10-25 | `da99cdc` | feat: about licenses privacy (#263) | G | About, licenses and privacy include external links; parent-only. Reuse license data for compliance |
| 2026-10-25 | `be01415` | chore: update AetherEngine and drop LibDTSX (#264) | A | AetherEngine update; LibDTSX dropped, update compliance notes |
| 2026-10-25 | `457cf84` | fix: make tvOS settings categories scrollable (#265) | A | tvOS settings scroll |
| 2026-10-25 | `93c10bc` | fix: restore last focused card when entering a rail on tvOS (#266) | A | tvOS focus restore |
| 2026-10-25 | `0b76b5a` | feat: library context menu (#268) | G | Library context menu includes manage and write actions |
| 2026-10-25 | `a8ef148` | feat: show subtitles on skip back (#267) | A | Subtitles on skip back |
| 2026-10-26 | `8f11ad6` | fix: scale detail hero height with screen width on iPad (#269) | A | iPad hero |
| 2026-10-26 | `aee74ff` | fix: add spacing below play button for tvOS info panel chevron (#271) | A | tvOS spacing |
| 2026-10-26 | `bafb24b` | feat: screenshot demo mode (#272) | G | Screenshot demo mode; must not be reachable in Plinx, which has its own demo |
| 2026-10-26 | `28e5c60` | fix: decode Plex section hidden flag leniently (#273) | A | Lenient hidden flag; library visibility is separate from content authorization |
| 2026-10-27 | `4cc0808` | chore: bump version to 1.3.3 (#274) | N | Version |
| 2026-10-27 | `975c1f3` | fix: ass embedded fonts (#275) | A | ASS fonts |
| 2026-10-27 | `680a64a` | fix: render ASS subtitles on the presented frame time (#276) | A | ASS timing |
| 2026-10-28 | `23af307` | feat: add pinch-to-zoom in the iOS player (#251) | A | Pinch zoom |
| 2026-10-28 | `0c5c324` | fix: add bottom padding to library detail tab picker (#286) | A | Padding |
| 2026-10-28 | `efadfe6` | feat: auto-rotate landscape videos on iPhone (#250) | A | Auto-rotate |
| 2026-10-28 | `a6fb28a` | feat: show episode title in player header (#291) | A\* | Episode title in header; interacts with patch 14 and Plinx title chrome |
| 2026-10-28 | `9566497` | fix: limit artwork tap area to its frame (#292) | A | Artwork tap area |
| 2026-10-28 | `708959c` | fix: rebuild ASS subtitle view when switching ASS tracks (#293) | A | ASS track switch |
| 2026-10-29 | `654a053` | fix: track secondary title (#295) | A | Track title |
| 2026-10-29 | `97098b1` | fix: jellyfin resume the in-progress episode when opening a series (#296) | A | Jellyfin resume |
| 2026-10-29 | `7153aa8` | fix: list every episode of a Jellyfin series for offline and downloads (#297) | A | Jellyfin episodes for offline |
| 2026-10-29 | `ae4a969` | fix: keep series episodes in place when marking one as watched (#299) | A | Episode list stability |
| 2026-10-29 | `3a78bfb` | fix: keep episode artwork at 16:9 for non-16:9 thumbnails (#300) | A | Episode artwork |
| 2026-10-29 | `c7892b1` | fix: keep offering a rewatched episode in progress on the series page (#301) | A | Rewatch progress |
| 2026-10-29 | `434a8e8` | feat: show playback in the system Now Playing controls (#302) | A | Now Playing; local only |
| 2026-10-29 | `7c7589c` | chore: test infrastructure (#304) | A | Test infrastructure |
| 2026-10-29 | `a997ff6` | feat: support Plex editions (#303) | A | Plex editions |
| 2026-10-29 | `7fcca13` | chore: offline and playback tests (#305) | A | Tests |
| 2026-10-29 | `e83ea07` | feat: play Jellyfin theme songs on detail pages (#306) | A | Jellyfin theme songs |
| 2026-10-29 | `7c23327` | fix: pin the player info panel to the bottom on iPad (#310) | A | iPad info panel |
| 2026-10-30 | `6f24d40` | fix: restore external Plex subtitles when resuming playback (#311) | A | External subtitle resume |
| 2026-10-30 | `74bc4b2` | fix: offer mark as unwatched for in-progress items in card menus (#312) | A | Mark unwatched |
| 2026-10-30 | `f6b26db` | feat: show previous items in the player queue (#313) | A\* | Previous queue items; check launcher coverage |
| 2026-10-30 | `40b6553` | feat: show skip segments on the player timeline (#316) | A\* | Skip segments on the timeline; see the timeline section |
| 2026-10-30 | `c94d012` | feat: add custom video zoom on iOS and tvOS (#318) | A | Video zoom |
| 2026-10-30 | `b633c83` | feat: adjust tvOS video zoom with a stepper bar (#319) | A | tvOS zoom |
| 2026-10-30 | `1b5bf2c` | fix: bound unsized card artwork and decode Plex images off the main actor (#320) | A | Image decoding |
| 2026-10-30 | `14e4af9` | fix: improve home refresh (#321) | A | Home refresh |
| 2026-10-31 | `2cfac88` | feat: add option to play from continue watching (#324) | A\* | Play from Continue Watching must pass the Plinx launcher |
| 2026-10-31 | `1dc446f` | feat: add series artwork settings for episode and season cards (#325) | A | Series artwork |
| 2026-10-31 | `1318d21` | feat: download external subtitle files (#326) | A | Subtitle files in downloads |
| 2026-10-31 | `026d5d3` | fix: match search results across servers and show copy quality (#327) | A\* | Cross-server search; replay patch 06 |
| 2026-10-31 | `ebedb31` | feat(downloads): check storage and show byte progress (#315) | A\* | Download storage and byte progress; overlaps the download patches |
| 2026-10-31 | `359edc1` | feat: browse items shared individually on Plex (#328) | G | Individually shared items are a new content source; filter seam needed |
| 2026-10-31 | `a8b40ff` | fix: keep spoiler protection on episode artwork (#329) | A | Spoiler artwork |
| 2026-10-31 | `ada8e8f` | chore: include Shared folder in tvOS target (#330) | A\* | tvOS target now includes `Shared`; reconcile Plinx tvOS source scoping |
| 2026-10-31 | `8a4763e` | chore: bump SwiftFormat to 0.64.5 and reformat (#331) | N | Reformat |
| 2026-10-31 | `450e5cc` | feat(player): lock all controls along with orientation (#332) | A | Control lock |
| 2026-11-01 | `273f03e` | feat: add setting to hide watched badges (#333) | A | Hide watched badges |
| 2026-11-01 | `3983bb0` | feat: add default playback speed setting (#334) | G | Default speed; Plinx removed speed control, so hide it |
| 2026-11-01 | `c05b6d7` | feat(tvos): add sidebar navigation option (#335) | A | tvOS sidebar option |
| 2026-11-01 | `f2a3d88` | feat: remove items from Continue Watching on Plex (#336) | G | Remove from Continue Watching writes to the server; hide in kid UI |
| 2026-11-01 | `d485206` | feat: refresh and analyze media from a Manage menu (#337) | G | Manage menu: parent-only (parental gate) |
| 2026-11-01 | `454a467` | feat: scan, refresh, analyze and empty trash from a library Manage menu (#340) | G | Library Manage menu: parent-only |
| 2026-11-01 | `ba8aa66` | feat: add a default sleep timer setting (#341) | A | Default sleep timer |
| 2026-11-01 | `e5d3119` | feat: choose and upload artwork from the Manage menu (#342) | G | Manage artwork: parent-only |
| 2026-11-01 | `31215a1` | feat: open Seerr trailers externally (#343) | R | Seerr trailers open externally; hidden in kid UI, parent surfaces only |
| 2026-11-01 | `61f1eb2` | fix: show menu action results as toasts (#344) | A | Toasts |
| 2026-11-01 | `719563b` | feat: delete media from the server (#345) | G | Delete from server: parent-only with fresh PIN and confirmation |
| 2026-11-01 | `3c876fb` | feat: fix match, identify and unmatch from the Manage menu (#346) | G | Match/unmatch: parent-only |
| 2026-11-02 | `f269d29` | feat: edit metadata from the Manage menu (#349) | G | Metadata edit: parent-only |
| 2026-11-02 | `f2cee4c` | feat: edit Plex advanced settings from the Manage menu (#348) | G | Advanced settings: parent-only |
| 2026-11-02 | `58a9935` | feat: open Seerr trailers in the YouTube app on tvOS (#350) | R | YouTube app hand-off; hidden in kid UI, parent surfaces only |
| 2026-11-02 | `f5f6b0e` | ui: move library visibility and pinning to a dedicated settings page (#352) | G | Library visibility page conflicts with Plinx-owned visibility |
| 2026-11-02 | `3606636` | feat: choose the startup screen (#351) | A | Startup screen |
| 2026-11-02 | `3ae1535` | chore: update AetherEngine (#354) | A | AetherEngine update |
| 2026-11-02 | `cdef43f` | feat: add a configurable bottom margin for subtitles (#353) | A | Subtitle margin |
| 2026-11-02 | `2d6232c` | feat: add fast navigation to library browsing on iOS and macOS (#356) | A | Fast navigation |
| 2026-11-02 | `ab269af` | feat: remember the selected tab in each library (#357) | A | Remember tab |
| 2026-11-02 | `f4b1d88` | fix: percent-encode reserved characters in Seerr query parameters (#359) | A | Seerr query encoding |
| 2026-11-02 | `30ee290` | feat: add night mode and dialogue boost audio enhancements (#358) | A | Night mode and dialogue boost |
| 2026-11-02 | `b6bd7d9` | ui: rework library browse filters (#360) | A\* | Browse filters rework; replay `itemFilter` |
| 2026-11-02 | `c982f55` | feat: option to merge Jellyfin Next Up into Continue Watching (#362) | A | Jellyfin Next Up merge |
| 2026-11-02 | `b38c394` | feat: add playback statistics to the player (#363) | A | Playback statistics |
| 2026-11-03 | `6c06b1f` | feat: add a featured hero carousel to the home (#365) | G | Hero carousel aggregates trending and curated items; must be filtered |
| 2026-11-03 | `86ad99d` | fix: hide tvOS player controls on back before exiting (#366) | A | tvOS back |
| 2026-11-03 | `eac963f` | feat: add picture in picture and background audio settings on iOS (#367) | G | Picture in Picture and background audio settings; parent-only |
| 2026-11-03 | `44600a9` | fix: keep detail scroll position when returning from a pushed page (#368) | A | Scroll position |
| 2026-11-03 | `955affb` | fix: reposition tvOS episode rail after playback (#369) | A | tvOS rail |
| 2026-11-03 | `58fae29` | feat: split iOS player settings into tracks and settings buttons (#370) | A\* | Split iOS player settings; Plinx replaces `PlayerControlsView` |
| 2026-11-03 | `f35acbe` | fix: stop up next badge from overlapping spoiler indicator on tvOS (#371) | A | Badge overlap |
| 2026-11-04 | `49d4a53` | feat: redesign live TV (#372) | R | Live TV |
| 2026-11-04 | `e7b5b4b` | feat: player subtitle appearance (#373) | A | Subtitle appearance |
| 2026-11-04 | `f13700d` | feat: subtitle search fewer clicks (#374) | G | Subtitle search |
| 2026-11-04 | `6e33fc0` | feat: add account audio and subtitle preferences (#375) | A | Account track preferences |
| 2026-11-04 | `9a9d233` | feat: search and apply missing subtitles automatically (#376) | G | Automatic subtitle search writes to the server; keep it off |
| 2026-11-05 | `909ae8f` | fix: refresh posters when a library reorders (#381) | A | Poster refresh |
| 2026-11-05 | `cddcba9` | ui: replace the system More tab with a custom one on iPhone (#380) | N | Plinx owns its tabs |
| 2026-11-05 | `a66f7a3` | ui: keep the tab bar visible on iOS detail pages (#382) | A\* | Tab bar on detail pages; check Plinx tabs |
| 2026-11-05 | `2ff4ffd` | fix: make the device language subtitle test locale independent (#383) | N | Test |
| 2026-11-05 | `577bfde` | feat: sync playback progress and watched state to Trakt and Simkl (#384) | R | Trakt and Simkl send viewing history to third parties; exclude `Shared/Trackers` and stub it |
| 2026-11-06 | `1fa9971` | fix: stop the tvOS back button from closing the app too early (#385) | A\* | tvOS back button; Plinx owns the tvOS root, so port the logic |
| 2026-11-06 | `738c31a` | chore: build tvOS on a generic simulator destination in CI (#386) | N | CI |
| 2026-11-07 | `7e97dd5` | feat: add a playback buffering setting (#391) | A | Buffering setting |
| 2026-11-07 | `5ad8a97` | fix: offer the downloaded copy when playback fails on a lost server (#392) | A\* | Downloaded-copy fallback must respect ownership scoping |
| 2026-11-07 | `d775d64` | feat: sort live TV channels by number or name (#393) | R | Live TV |
| 2026-11-08 | `6b407a5` | feat: show playback progress on the tvOS Top Shelf (#394) | R | Top Shelf progress shows viewing history outside the gate; Top Shelf stays excluded |
| 2026-11-08 | `f8cd117` | chore: hide Trakt until its API app is approved | R | Trakt |
| 2026-11-10 | `436735c` | feat: re-enable Trakt with the production API app (#395) | R | Trakt production app |
| 2026-11-11 | `f875d0a` | chore: bump version to 1.3.4 (#397) | N | Version |
| 2026-11-11 | `95784dd` | fix: decode Plex subtitle search scores sent as numbers (#398) | A | Subtitle search score decoding (search stays gated) |
| 2026-11-11 | `cd72f21` | fix: decode Plex items and hubs from lookalike servers leniently (#399) | A | Lenient item and hub decoding |
| 2026-11-11 | `4ac7eaa` | fix: accept wrapped Jellyfin item lists from lookalike servers (#400) | A | Jellyfin wrapped lists |
| 2026-11-12 | `a9750fc` | fix: stop re-rendering the library listing on every scroll frame (#404) | A | Fixes #356; not present at the pin |
| 2026-11-12 | `d25cd20` | fix(player): restore auto-rotation after returning from the background (#402) | A | Fixes #250; not present at the pin |
| 2026-11-13 | `739a4a0` | fix: default subtitle search to the account subtitle language (#405) | A | Subtitle search language |
| 2026-11-13 | `32f5946` | fix: stop episode lists from jumping and freezing on detail pages (#406) | A | Fixes a later episode-row regression; not present at the pin |
| 2026-11-13 | `b631e07` | chore: move screenshot simulators to the 27.2 runtimes | N | CI |
| 2026-11-14 | `1ffe63a` | fix: extend the home hero under the horizontal safe area (#408) | A | Hero safe area |
| 2026-11-14 | `8b14d79` | fix: smooth out scrolling along the tvOS home rows (#409) | A | Fixes later hero and shadow code; not present at the pin |
| 2026-11-15 | `1c16820` | fix(seerr): show seasons correctly when Seerr uses TheTVDB (#412) | A | Seerr TVDB seasons |
| 2026-11-16 | `4183f30` | fix(seerr): remove the light rim around request cards and posters (#411) | A | Seerr card rim |
| 2026-11-17 | `c1c82c9` | feat(player): add a tvOS system player style (#413) | G | tvOS system player style bypasses Plinx player chrome; force the custom style |
| 2026-11-17 | `40117c5` | feat(player): add a play from start button to the info panel (#414) | A | Play from start |
| 2026-11-17 | `c449b92` | fix: smooth out scrolling in the tvOS library grid (#416) | A\* | tvOS grid paging; replay patch 02 compact pagination |
| 2026-11-17 | `f3bf11b` | fix(seerr): stop cancelled discover loads from showing an error (#410) | A | Seerr cancelled loads |
| 2026-11-18 | `a4486f4` | ci: deploy TestFlight platforms in parallel jobs (#418) | N | CI |
| 2026-11-19 | `ccf2543` | feat(profiles): ask for the profile again after 15 minutes away (#419) | G | 15-minute profile re-prompt could offer adult profiles; disable or gate it |
| 2026-11-19 | `0417dcb` | fix(downloads): retry failed downloads and reject error responses (#421) | A\* | Retry and resume; the error-response check duplicates patch 07's stricter validator |
| 2026-11-19 | `0f965c1` | feat(copies): show library and quality of copies and pick one from Continue Watching (#420) | A | Copy picker |
| 2026-11-19 | `8c349c0` | fix(player): let focus reach Go Live from the tvOS system player buttons (#423) | N | tvOS system player and Live TV |
| 2026-11-19 | `b155757` | fix(livetv): read Plex channel numbers and HD flag from lineup channels (#422) | N | Live TV |
| 2026-11-21 | `0235d27` | feat(spoilers): hide unwatched episode titles in full spoiler protection (#425) | A | Spoiler titles |
