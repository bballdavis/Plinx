# Strimr Upstream Audit — 2026-07-25

Baseline refreshed on 2026-07-26 before migration work began.

## Implementation Status

Implementation is underway on the feature-specific pair:

- Plinx `feat/strimr-aether-upgrade`
- Strimr `feat/plinx-upstream-seams`

The Strimr branch starts directly from audited upstream `e0a8cbc`; it does not
merge the accumulated `atv` history. The current implementation has:

- pinned and resolved AetherEngine at the audited revision
- removed the MPVKit dependency and obsolete MPV/VLC adapters
- restored clip support, strict Plex boolean decoding, filtered pagination,
  hidden-library search parity, clear-title-logo selection, and a SharePlay
  presentation policy on the new baseline
- retained Plinx-owned safety authorization, library presentation, branding
  assets, maximum-volume policy, and the no-op reporter
- generated the Plinx Xcode project and compiled the Strimr macOS target as a
  shared-source compatibility check

iOS and tvOS build/test gates remain mandatory and require an Xcode installation
with those platform SDKs and simulator runtimes.

## Decision

Plinx should move to the current Strimr architecture, but it should not merge the
existing `atv` or `plinx-patches` history into upstream `main`.

The recommended path is a controlled rebase of the Plinx integration onto the
audited upstream commit `e0a8cbc`, with only the still-required generic seams
reimplemented. This is worthwhile because the current upstream line replaces the
old MPV/VLC player layer with AetherEngine, fixes lifecycle and tvOS focus issues,
adds fresh-data refresh, hub drill-down, richer media details, ratings, subtitle
customization, server recovery, and an actively maintained playback stack.

The work is high risk but lower risk than continuing to extend the old fork. The
fork's player changes are now built around files upstream has deleted, and a
synthetic merge already reports conflicts across the player, downloads, session,
settings, media-detail, library, and localization layers.

This recommendation is conditional on four non-negotiable acceptance gates:

1. Plinx safety filtering remains fail-closed on iOS and tvOS.
2. Sentry and other collection remain absent from the Plinx binary.
3. SharePlay initiation and other social/external actions remain hidden from
   kid-facing Plinx surfaces.
4. iOS 17.5 and tvOS 17 remain supported unless a separately approved product
   decision changes those minimums.

## Audited Revisions

| Repository state | Revision | Meaning |
|---|---|---|
| Historical Strimr base | `2ecbced` | Upstream base on which Plinx patches were reapplied |
| Last recorded submodule pin | `281a0b3` | Plinx fork commit pinned before the sibling-checkout migration |
| Strimr stable release | `8ce61ac` / `1.1.0` | Four commits after the historical base |
| Current Strimr upstream | `e0a8cbc` | Audited `wunax/strimr` `main` head on 2026-07-26 |
| Current Strimr fork branch | `02d17bb` | `origin/atv`, plus uncommitted player/UI work |
| Current Plinx branch point | `f955f02` | Plinx revision used for the clean compatibility spike |

The stable-release delta is small: four commits, three files, 56 insertions, and
8 deletions. The current-main delta is material: 66 commits, 248 files, 14,710
insertions, and 4,976 deletions. Upgrading only to `1.1.0` would take integration
effort without gaining the architectural improvements that justify the work.

## Upstream Change Review

### Adopt as part of the new baseline

| Upstream area | Important changes | Plinx disposition |
|---|---|---|
| Playback engine | VLC and the in-tree MPV bridge removed; AetherEngine introduced and repeatedly stabilized | Adopt, pin AetherEngine to the audited revision, remove obsolete Plinx factories/stubs |
| Playback quality | HDR/Dolby Vision paths, lossless-audio mode, bitmap subtitles, subtitle appearance controls, badge cleanup | Adopt after device playback validation |
| Playback lifecycle | Background reload, cancellation handling, media-transition reconciliation | Adopt; discard old MPV/VLC lifecycle patches |
| Data freshness | Automatic refresh gates and refresh-on-return behavior | Adopt while retaining safety decorators |
| Home and hubs | Correct season selection, “View All,” hub detail support | Adopt after filtered hub/item parity tests |
| Media detail | Dedicated season/episode details, completed-series fallback, Plex ratings | Adopt; supply Plinx-compatible rating assets |
| Session handling | Recoverable server-selection failures and cancellation-aware hydration | Adopt |
| tvOS | Focus fixes, carousel padding, subtitle positioning, on-deck scrolling | Adopt, then reapply only verified Plinx focus treatment |
| Shared code layout | Download and library view models moved into `Shared` | Adopt and simplify `project.yml` source routing |

### Compile but keep dormant or excluded

| Upstream area | Reason |
|---|---|
| SharePlay | Starting a social playback session is not appropriate in kid-facing UI without a product and parental-gate decision. Inject the coordinator only to satisfy engine dependencies and hide initiation controls. |
| tvOS Top Shelf | The extension can surface content outside Plinx's gated UI. Do not ship it until it consumes Plinx safety policy and has a separate security review. |
| macOS target | Plinx has no approved macOS product scope. Shared compatibility is useful, but no Plinx macOS target should be created in this migration. |
| Sentry and Fastlane Sentry integration | Conflicts with Plinx's zero-collection baseline. Continue excluding upstream `ErrorReporter` and provide the no-op Plinx implementation. |
| Strimr signing/TestFlight workflows | They are upstream release infrastructure, not reusable Plinx build configuration. |

## Dependency, Platform, and Compliance Impact

- Current upstream resolves AetherEngine at
  `d882f47811757f8ebbf44e791abf96416262b49a`. Pin that revision in Plinx so a
  sibling update cannot silently change playback behavior.
- AetherEngine's package floor is iOS 16, tvOS 16, and macOS 14, so the engine
  itself does not require Plinx to raise its iOS 17.5/tvOS 17 floors. Current
  Strimr application targets use newer SDK APIs and deployment settings,
  including tvOS 26; those call sites must be compiled and gated individually.
- AetherEngine is LGPL-3.0 with an App Store/DRM exception. Its FFmpegBuild
  dependency is dynamically linked under LGPL-2.1-or-later. Before release,
  Plinx must preserve notices and license texts, link the corresponding source
  and build information from an adult-facing legal/settings surface, and confirm
  the embedded frameworks satisfy the documented relinking obligations.
- AetherEngine states that it has no external analytics. Its `LiveTelemetry`
  implementation is an in-process diagnostics surface, and the audited source
  did not reveal an outbound analytics client. Release validation must still
  inspect the resolved dependency graph, binary, privacy manifest, and runtime
  traffic rather than relying only on that claim.
- AetherEngine also resolves FFmpegBuild, LibDovi, and SMBClient. Plinx currently
  needs only the core AetherEngine product, not the SMB product; keep SMBClient
  out of the linked application unless a reviewed feature requires it.

## Fork Change Inventory

This matrix covers the committed `origin/atv` history, the isolated `pr/*`
branches, feature branches, and the uncommitted Strimr working tree.

| Fork capability | Current upstream status | Decision |
|---|---|---|
| Plex `clip` media type and Other Videos support | Still absent | Re-port and contribute as a focused PR |
| `itemFilter` and `hubFilter` seams | Still absent | Re-port; required for downstream safety without copying upstream view models |
| Compact tvOS pagination after filtering | Still absent | Include with the filter seam so rejected rows do not leave focus holes |
| Flexible decoding of Plex boolean-like values | Still absent (`smart` remains `Bool?`) | Contribute as an independent bug fix |
| Clear/title-logo art | Still absent | Re-port logo-only behavior onto current media-detail code |
| External ratings | Implemented independently by upstream PR #107 | Drop the fork implementation; use upstream models and presentation |
| Explicit default-server preference | Upstream remembers the selected server but has no separate explicit preference | Propose issue-first; remove Plinx-specific legacy key migration |
| Recently-added identifier variants | Upstream still matches only `recentlyadded` | Contribute a pure identifier classifier; drop public title logging and English title matching |
| Search hidden-library parity | Still absent | Contribute; hidden libraries should not reappear through search |
| Search with no forced movie/TV filter | Still absent | Include with search parity so clips and future supported types can appear |
| Download HTTP response validation | Still absent | Contribute as download integrity hardening |
| Download-index error handling | Upstream still swallows persistence errors | Contribute non-sensitive diagnostics and preserve the last valid index |
| Offline resume/watched state | Still absent | Contribute separately from download-file integrity |
| Download network recheck/probe | Partly product-driven and not independently evidenced | Keep in Plinx until a reproducible upstream bug is documented |
| Download quality selection/transcode profiles | Fork ultimately bypasses the selected quality because Plex background transcoding is not implemented safely | Do not upstream in its current form |
| Download artwork layout and library-agent metadata | Primarily Plinx presentation behavior for Other Videos | Keep in Plinx unless upstream asks for the general metadata |
| Old MPV simulator/HDR fixes | MPV implementation deleted upstream | Obsolete; archive the PR branch |
| MPV/VLC volume, lifecycle, buffering, and session patches | Superseded by AetherEngine | Do not replay |
| Maximum-volume cap | Kid-safety policy | Keep in Plinx |
| Pause when the screen turns off | Upstream Aether lifecycle now stops and reloads in background | Re-evaluate in Plinx; do not replay the old player patch |
| Optimistic watched-status environment | Used by Plinx quick actions and UI composition | Keep in Plinx unless upstream introduces equivalent actions |
| Kids tabs, hidden controls, Plinx product identifiers, branding, and player chrome | Plinx-owned product behavior | Never upstream |
| Dynamic authentication polling | No Plex API evidence or regression test supports the chosen backoff | Do not upstream yet |
| Host-app Plex product identity and encoded auth URL | Upstream hard-codes `Strimr` in Plex request headers and auth URLs | Replay the generic host-bundle identity seam until upstream accepts it; PIN creation and browser claim identity must remain identical |
| Direct-server bootstrap and UI-test token hooks | Plinx offline/UI-test infrastructure | Keep in Plinx |
| Library sizing, artwork selection, and focus styling | Upstream has overlapping but different tvOS changes | Reapply only after screenshots and focus tests show a remaining defect |
| Uncommitted speed removal and player-control restyling | Product/UI preference, not a generic engine fix | Keep out of the upstream contribution queue |
| Uncommitted `scrollClipDisabled` and focus halo | Potential generic tvOS fix, but overlaps upstream PR #83 | Require a current-upstream reproduction before proposing |

## Compatibility Spike

A clean Plinx worktree at `f955f02` was paired with a clean Strimr worktree at
`3d7d593`.

Unmodified project generation failed for three concrete reasons:

1. Plinx still references the sibling `MPVKit` package in `project.yml`.
2. The tvOS target still names
   `Strimr-iOS/Features/Downloads/DownloadManager.swift`.
3. The tvOS target still names
   `Strimr-iOS/Features/Downloads/DownloadModels.swift`.

In the disposable worktree, replacing MPVKit with AetherEngine at
`d882f47811757f8ebbf44e791abf96416262b49a`, removing the two obsolete download
paths, and excluding the obsolete Plinx player factory/launcher allowed XcodeGen
to create the project.

Package resolution then exposed a fourth migration requirement:
`Packages/PlinxCore` independently declares MPVKit. Keeping that dependency
alongside AetherEngine fails resolution because MPVKit and AetherEngine's
FFmpegBuild dependency export the same FFmpeg module names. Removing the obsolete
PlinxCore MPVKit dependency in the disposable worktree allowed the AetherEngine
graph to resolve successfully.

Source compilation could not start on the audit machine because Xcode has only
the macOS 26.5 SDK installed; the iOS 26.5 platform and simulator runtime are
absent. `xcodebuild` therefore stopped with “Unable to find a destination” after
package resolution. This is an environment limitation, not evidence that the
migrated source compiles. The first implementation PR must run the generated
iOS and tvOS builds on a machine with both platforms installed and treat the
resulting compiler diagnostics as migration work, not deferred cleanup.

A synthetic three-way merge of `origin/atv` and upstream `main` is not a viable
upgrade method. It reports content or modify/delete conflicts in at least these
areas:

- `DownloadManager`, `HomeViewModel`, library view models, and `SessionManager`
- `AppSettings`, `SettingsManager`, Plex media models, and watched-status UI
- iOS media-detail, season/episode, player, and wrapper views
- tvOS library view models
- deleted MPV/VLC player files and deleted Watch Together files
- localization and `.gitignore`

The correct migration is therefore a new fork branch from upstream, not a merge
or rebase of the accumulated fork branch.

## Upgrade Blueprint

### Phase 1 — New engine baseline

1. Create a new Strimr fork branch directly from `e0a8cbc`.
2. Pin AetherEngine to the exact audited revision instead of following its
   moving `main` branch.
3. Update `PlinxApp/project.yml` for moved shared/download files and remove
   obsolete MPV/VLC excludes and dependencies.
4. Remove `PlinxPlayerFactory`, the VLC stub, and the playback-player sanitizer.
   Replace the old launcher with a Plinx-owned fail-closed authorization
   boundary that delegates presentation to Aether-backed Strimr playback.
5. Update the composition root to inject `SharePlayCoordinator` in a dormant
   configuration.

### Phase 2 — Restore Plinx boundaries

1. Re-port only the filtering seams and clip-model support required by Plinx.
2. Update adapters and fixtures for upstream media ratings and changed model
   initializers.
3. Keep the no-op `ErrorReporter`; confirm Sentry is absent from the resolved
   Plinx graph and linked binary.
4. Hide SharePlay initiation in a Plinx-owned layer. Carry a minimal generic
   fork seam only if a Plinx adapter cannot do so without copying a large
   upstream view.
5. Import only the required rating assets, never the full Strimr asset catalog,
   and preserve applicable notices.

### Phase 3 — Platform validation

1. Compile and test at iOS 17.5 and tvOS 17.
2. Feature-gate or exclude upstream UI that requires a newer OS; do not raise
   the Plinx floor as an incidental merge resolution.
3. Run safety, live-library parity, navigation, downloads, and device playback
   checks.
4. Validate H.264 and HEVC playback, resume, seeking, background/foreground,
   audio/subtitle selection, offline playback, and representative HDR content.

### Phase 4 — Retire the old fork

1. Move CI and branch pairing to the new exact fork branch only after both
   platforms pass.
2. Archive obsolete MPV/VLC and already-upstreamed PR branches.
3. Keep each remaining generic patch traceable to an issue or contribution plan.
4. Update architecture, runtime-build, setup, branch-pairing, privacy, and
   testing documentation in the upgrade PR.

## Contribution Plan Index

The individual plans are stored in
`docs/maintenance/strimr-contributions/`:

1. [Plex clip media support](strimr-contributions/01-plex-clip-media-support.md)
2. [Library filtering seams](strimr-contributions/02-library-filtering-seams.md)
3. [Flexible Plex boolean decoding](strimr-contributions/03-flexible-plex-boolean-decoding.md)
4. [iOS clear title logos](strimr-contributions/04-ios-clear-title-logos.md)
5. [Recently-added hub classification](strimr-contributions/05-recently-added-hub-classification.md)
6. [Search visibility parity](strimr-contributions/06-search-visibility-parity.md)
7. [Download integrity and index recovery](strimr-contributions/07-download-integrity-and-index-recovery.md)
8. [Offline playback progress](strimr-contributions/08-offline-playback-progress.md)
9. [Explicit default-server preference](strimr-contributions/09-explicit-default-server-preference.md)
10. [SharePlay presentation capability](strimr-contributions/10-shareplay-presentation-capability.md)
11. [Plex Download Queue transcoding](strimr-contributions/11-download-queue-transcoding.md)
12. [Host-app Plex authentication identity](strimr-contributions/12-plex-authentication-product-identity.md)

## Upstream Commit Appendix

Every commit in `2ecbced..e0a8cbc` was reviewed:

| Date | Commit | Change |
|---|---|---|
| 2026-02-24 | `7118be8` | Set tvOS deployment minimum to 26 |
| 2026-02-24 | `d99bd4a` | Fix tvOS player control focus |
| 2026-02-26 | `3d9fe92` | Bump build |
| 2026-02-26 | `8ce61ac` | Update README; release 1.1.0 |
| 2026-06-24 | `b260d66` | Remove VLC playback |
| 2026-07-07 | `d8efa61` | Prefer a non-blank Watch Together display name |
| 2026-07-07 | `c42d498` | Replace player with AetherEngine |
| 2026-07-07 | `16451c8` | Simplify tvOS seek feedback |
| 2026-07-07 | `719c12c` | Select the current Continue Watching season |
| 2026-07-08 | `923263a` | Add fresh-data refresh |
| 2026-07-08 | `5b0f822` | Increase tvOS carousel focus padding |
| 2026-07-09 | `7597f97` | Add View All for Plex hubs |
| 2026-07-09 | `9e29cf3` | Bump version/build |
| 2026-07-09 | `b95f6f2` | Fix translation spelling |
| 2026-07-09 | `4a6ad35` | Increase library sidebar spacing |
| 2026-07-09 | `646db59` | Reduce tvOS player focus overlap |
| 2026-07-10 | `da6c1fc` | Add lossless-audio setting |
| 2026-07-11 | `b2096f5` | Update AetherEngine to 5.0.1 |
| 2026-07-11 | `eb7eb78` | Support bitmap subtitle canvas sizing |
| 2026-07-11 | `beea0ad` | Bump build |
| 2026-07-11 | `f2474a8` | Update AetherEngine to 5.0.2 |
| 2026-07-11 | `a4ea856` | Align player badge sizing |
| 2026-07-11 | `1f38655` | Bump build |
| 2026-07-12 | `74a00bc` | Add tvOS Top Shelf |
| 2026-07-12 | `1db7b87` | Keep tvOS subtitles stationary with controls |
| 2026-07-12 | `d292b42` | Document playback/platform support |
| 2026-07-12 | `51e9fbb` | Add TestFlight link |
| 2026-07-12 | `fd097e1` | Update AetherEngine to 5.0.3 |
| 2026-07-12 | `23df86d` | Add version-bump workflows |
| 2026-07-12 | `796ef15` | Bump build |
| 2026-07-12 | `52558eb` | Add Top Shelf device capabilities |
| 2026-07-13 | `5c511ae` | Ignore request cancellation errors |
| 2026-07-13 | `d3658d1` | Recover from server-selection failures |
| 2026-07-13 | `fcea3b7` | Add TestFlight deployment and remove Carthage setup |
| 2026-07-13 | `631e664` | Avoid duplicate Xcode authentication flags |
| 2026-07-13 | `c67aac8` | Configure Match signing |
| 2026-07-13 | `3b3dac8` | Configure platform-specific signing |
| 2026-07-14 | `5005fef` | Add Sentry Fastlane plugin |
| 2026-07-14 | `382ad7b` | Auto-scroll to the on-deck tvOS episode |
| 2026-07-14 | `1aabb05` | Update Sentry |
| 2026-07-14 | `36f77bf` | Update AetherEngine to 5.0.5 |
| 2026-07-17 | `884ca6b` | Move AetherEngine package source |
| 2026-07-17 | `2a2a657` | Generalize player integration names |
| 2026-07-17 | `2de8ff5` | Update SwiftFormat rules |
| 2026-07-17 | `936acdc` | Replace Watch Together with SharePlay |
| 2026-07-17 | `229860e` | Add subtitle appearance customization |
| 2026-07-18 | `5e2d0ed` | Stabilize SharePlay startup |
| 2026-07-18 | `f16a495` | Ignore build folder |
| 2026-07-18 | `9e546a1` | Update AetherEngine revision |
| 2026-07-19 | `0bae729` | Start SharePlay outside FaceTime |
| 2026-07-19 | `80d5fbf` | Add iOS season/episode details and series fallback |
| 2026-07-20 | `a0664e9` | Add Plex ratings |
| 2026-07-20 | `f3bd213` | Align iOS media-detail secondary buttons |
| 2026-07-20 | `9ba73be` | Compact iOS episode titles |
| 2026-07-20 | `20ca232` | Update package revisions |
| 2026-07-21 | `f880bc6` | Keep SharePlay media transitions synchronized |
| 2026-07-21 | `f971b5f` | Reconcile SharePlay after media load |
| 2026-07-22 | `8cc77aa` | Synchronize SharePlay media transitions |
| 2026-07-24 | `a84ffee` | Add macOS app |
| 2026-07-24 | `a3d7287` | Align macOS signing |
| 2026-07-25 | `041194b` | Install macOS distribution certificate |
| 2026-07-25 | `d15ffb9` | Update package revisions |
| 2026-07-25 | `3d2467d` | Rebind SharePlay media replacements |
| 2026-07-25 | `3d7d593` | Synchronize SharePlay seeks after replacement |
| 2026-07-26 | `91ec975` | Preserve the player across SharePlay replacement |
| 2026-07-26 | `e0a8cbc` | Sync SharePlay joiners to saved progress |
