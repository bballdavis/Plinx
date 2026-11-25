# Upstream Strimr Provenance

Plinx began as a kid-safe skin over [Strimr](https://github.com/wunax/strimr),
an open-source Plex and Jellyfin client by Thomas (wunax) and contributors. On
2026-11-23 Plinx absorbed Strimr's source and became a single codebase. There is
no longer a separate Strimr directory, sibling checkout, pin, or seam contract.
See the [hard-fork plan](strimr-hard-fork-plan.md) for the decision.

| Field | Value |
|---|---|
| Absorbed upstream commit | `0235d271d6b444c45df3c071f9bd4482e2b0f6f1` (`wunax/strimr` `main`, 2026-11-21) |
| Absorbed on | 2026-11-23 |
| License | GPL-3.0, the same license as Plinx (`LICENSE`) |
| Last upstream feature review | 2026-11-23 ([commit triage](strimr-contributions/15-upstream-main-migration-plan.md)) |

## Where the upstream code lives

| Upstream path | Plinx path |
|---|---|
| `Shared/` | `PlinxApp/Core/` |
| `Strimr-iOS/Features/` | `PlinxApp/Platform/iOS/` |
| `Strimr-tvOS/Features/`, `Strimr-tvOS/Shared/` | `PlinxApp/Platform/tvOS/` |
| `Localizable.xcstrings` | `PlinxApp/Resources/Localizable.xcstrings` |
| `StrimrTests/` | `PlinxApp/CoreTests/` (compiled into `Plinx-iOS-UnitTests`) |

When Plinx already had its own version of a screen or helper, the upstream copy
was deleted, so each concept has one implementation. Upstream's macOS app, Top
Shelf extension, Trakt and Simkl sync, release tooling, and Sentry reporting
were not carried over.

## Downstream patches at absorption

Before the absorption Plinx built against its own fork, `bballdavis/strimr`,
at `67fd7bb`: 42 commits on top of upstream, described in contribution plans
01 to 14 under `strimr-contributions/` and in the
[commit triage](strimr-contributions/15-upstream-main-migration-plan.md). The port (reviewed 2026-11-24 on `feat/strimr-hard-fork`) rebuilt the
app on upstream `0235d27` and settled each patch as follows.

**Kept, rebuilt directly in the absorbed code:**

| Patch | Where it lives now |
|---|---|
| Plex product identity from the host app (`496caa0`, plan 12) | `PlexProductIdentity` and `PlexAuthURLBuilder` in `Core/Networking/Plex`; every Plex request sends `X-Plex-Product` from them |
| Playback authorization (`8d9412a`) | `isPlaybackAuthorized` on the iOS and tvOS `PlayerWrapper` and `PlayerView`, defaulting to `ContentSafetyGate`, enforced at the single load site and before autoplay, queue advance and SharePlay |
| No playback-speed control (`8d9412a`) | Speed pickers removed; the player always starts at 1x |
| Volume cap (`24d9689`) | `PlaybackSettings.maxVolumePercent` (same JSON key, default 70), `PlayerController.maximumVolume`, re-applied around every engine load |
| SharePlay presentation capability (`3ffa298`, plan 10) | `\.sharePlayPresentationPolicy`, now defaulting to `.hidden` so it fails closed |
| Buffering overlay switch (`9cf6cf0`) | `showsBufferingOverlay` on both player wrappers |
| Local playback state (`75052bd`, part) | Downloaded files never show the buffering spinner |
| Clip queue continuation (`bc3fdca`, plan 01) | A finished clip continues the queue like a movie |
| Download integrity and index recovery (`1ef6a7b`, plan 07) | `DownloadIntegrityValidator`; `DownloadManager` never overwrites an unreadable index and drops damaged entries one by one |
| Download space-savings guard (`0ecbfb1`, plan 11) | `DownloadSpaceSavingsPolicy`; the old Plinx `downloads.quality` setting maps to the nearest quality preset |
| Download enrollment and access scoping (`45e3113`, plan 13) | Rebuilt on upstream's `ownerID`. Old index entries with a profile scope keep that owner, and the Plinx records in `plinx.downloadOwnership.v1` are migrated once; downloads with no record stay unowned and parent-only. `DownloadOwnershipStore` is retired |
| Empty season reload (`b8eb163`) | `MediaDetailViewModel.selectSeason` reloads a season with no episodes |
| Player title interaction lifetime (`67fd7bb`, plan 14) | The iOS player passes title interactions to the Plinx controls |
| Offline artwork layout (`e44aed0`, data only) | `DownloadedMediaMetadata.artworkLayoutStyle` is kept and decoded from the old index |
| Recently-added hub variants (`22d929c`, plan 05) | Kept in the Plinx Home layer (`HomeRecentlyAddedProjection`) |
| Optimistic watched status (`10bc877`, `36fc2ee`) | Kept in the Plinx layer (`PlinxWatchStatusStore`, `\.watchedOverrides`) |

**Adopted from upstream instead:** Plex clip media (#174, plan 01), lenient
Plex booleans (plan 03), clear title logos (`TitleLogoView`, plan 04),
offline playback progress (plan 08), download network monitoring
(`OfflineCoordinator.availability`), download quality presets (#164) and the
Plex download queue, the season download picker, local playback state, and
multi-server sessions, which replace the explicit default-server preference
(plan 09) and the session bootstrap seams.

**Dropped:**

- The library filtering and search visibility seams (plans 02 and 06): the
  `SafeMediaServices` boundary filters every content call instead.
- The `DownloadQuality` enums, the post-download "actual savings" fallback,
  and validation of Plex's `/decision` response.
- `PlexAPIContext.operationSnapshot`: download ownership now comes from the
  services used.
- Artwork-layout reconciliation and the typed download library index
  (`7e4d78b`).
- Brand colors on the upstream track-selection row; Plinx owns tvOS track
  selection.
- The upstream media-detail action chrome patches: iOS uses the absorbed
  detail screen and tvOS keeps the Plinx detail page.
- macOS changes and formatting-only commits.

The tvOS target scoping commits were redone in `PlinxApp/project.yml`, and
localization commits are regenerated rather than replayed.

Persisted identifiers that came from Strimr, such as the Keychain key
`strimr.plex.authToken`, keep their original names. Renaming them would sign
existing families out.

Code and copy were renamed for Plinx. When porting, read upstream's
`StrimrProfile` as `PlinxProfile` and `StrimrWatchActivity` as
`PlinxWatchActivity`; the SharePlay activity identifier is
`com.bballdavis.plinx.watch`. Strings that say "Strimr" become "Plinx", and
string-catalog entries for screens Plinx does not ship were removed rather than
renamed.

## Taking upstream changes

Upstream is a source of ideas and fixes, not a dependency. Review it on a
regular schedule:

```bash
git fetch upstream
git log --oneline 0235d271d6b444c45df3c071f9bd4482e2b0f6f1..upstream/main
```

The `upstream` remote points at `wunax/strimr` with pushes disabled. Upstream's
paths no longer match Plinx's, so port each change by hand. Keep the upstream
commit in the message (for example, `Ported from wunax/strimr@<sha>`). Record
each review here and in the triage document. Judge every change against the
kid-safety, zero-collection, and no-external-links rules in `AGENTS.md`.

## Attribution

Strimr's copyright notices stay in the files that carry them. The about and
licenses surface credits Strimr. Contributions that are generic bug fixes can
still be offered upstream as pull requests.
