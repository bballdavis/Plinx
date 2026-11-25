# Absorbed Strimr Codebase

Plinx is one codebase. On 2026-11-23 it absorbed the source of
[Strimr](https://github.com/wunax/strimr), the open-source Plex and Jellyfin
client it used to build against, and that code is now Plinx code. There is no
sibling checkout, pinned engine commit, pairing branch, or seam contract. The
[upstream provenance page](../maintenance/upstream-strimr.md) records where the
code came from and how upstream changes are ported. The
[current dependencies](../maintenance/current-dependencies.mdx) page shows the
absorbed upstream base and the exact package pins.

## Layers

Each app target (`Plinx-iOS`, `Plinx-tvOS`) compiles one module from these
folders in `PlinxApp/`, plus the local packages and Swift packages below.

| Layer | Path | Owns |
|---|---|---|
| App shell | `App/` | Composition root (`PlinxApp.swift`), lifecycle hardening, `ParentalAccessCoordinator`, settings sanitizing, the App Review demo, UI-test bootstraps, Youtarr |
| Plinx presentation | `Views/`, `ViewModels/`, `Adapters/` | Root tabs and onboarding, Home, Library, Search, detail screens, player chrome and timeline, parent settings, downloads grid, playback launch, watched state |
| Shared media stack | `Core/` | Sessions and accounts, the provider layer, the safety boundary, feature view models, player controller, models, networking, offline store (iOS), settings store |
| Platform screens | `Platform/iOS/`, `Platform/tvOS/` | Upstream platform screens Plinx kept: player wrappers and views, detail and library pieces, downloads (iOS), settings sections |
| Domain package | `Packages/PlinxCore` | `SafetyPolicy`, `SafetyInterceptor`, rating normalization, parental gate logic |
| Design package | `Packages/PlinxUI` | Theme, brand components, loading and focus affordances |

Swift packages, pinned exactly in `PlinxApp/project.yml`:

- **AetherEngine:** the playback engine, used only by the app targets.
- **GRDB:** the offline store.
- **SwiftAssRenderer:** ASS and SSA subtitle rendering.

`Core/` and `Platform/` keep upstream's folder shapes so that upstream changes
are easy to find and compare. They are not vendored: edit them in place.

### One implementation per concept

Where Plinx already had its own version of an upstream type, the upstream copy
was deleted and upstream callers now use the Plinx one. This covers:

- the player timeline, iOS player controls and buttons, and the tvOS player
  buttons and track selection
- the playback launcher
- sign-in, server and profile selection
- the root tabs and content view
- the backdrop gradient and rating label
- the downloads settings screen
- the no-op `ErrorReporter`

Do not reintroduce overrides by excluding a file and declaring a same-named
type elsewhere. Change the one implementation instead.

The tvOS target still excludes some `Core/` files in `project.yml`, either
because they are iOS-only (downloads, the offline store) or because Plinx has
its own tvOS screen. Keep exclusions to those two reasons. Delete a file that
neither target reaches.

## Composition And Sessions

`PlinxApp.swift` builds the upstream stack in upstream's order:

- `SettingsManager`
- `SessionManager`, which owns the `ServerRegistry`
- `LibraryStore`
- `SeerrStore`
- `SharePlayCoordinator`
- `MainCoordinator`
- `DownloadManager` and `OfflineCoordinator` (iOS only)

It adds the Plinx objects: `ParentalAccessCoordinator`, the watched-status
store, the playback launch and playback coordinators, the theme, and the
computed `SafetyPolicy`. All of them go into the SwiftUI environment.

`PlinxContentView` switches on `SessionManager.status`:

| Status | Shown |
|---|---|
| `hydrating` | Plinx loading screen, never an offline warning |
| `needsAccount` | Provider choice and sign-in (Plex or Jellyfin) |
| `needsProfileSelection` | Plinx profile picker |
| `migrationFailed` | Plinx connection recovery |
| `ready` | Root tabs |

The environment does not hold a Plex request context. Screens get a server's
services from `registry.services(for: ServerIdentity)` or
`registry.connectedServices`, or use upstream view models that take
`sessionManager` and `settingsManager`. Plex and Jellyfin build their services
in `Core/Providers`; the protocols are in `Core/Services/Protocols`.

## Safety Boundary

Every title a family sees passes one boundary in `Core/Safety`.

- **`ContentSafetyGate`** holds the active `SafetyPolicy` and whether the
  parental gate is unlocked. `PlinxApp` keeps both in sync with the parent's
  settings and `ParentalAccessCoordinator`. The gate judges a title on its own
  content rating against the ceiling for that rating's scale. A missing or
  unrecognized rating is rejected unless the parent allows unrated content.
  Adult-only ratings are always rejected. Each policy change bumps
  `revision`, which reloads Home and rebuilds the tab shell.
- **`SafeMediaServices`** wraps every service a provider builds. The wrap
  happens inside `MediaServices.init`, so no unwrapped `MediaServices` exists
  for Plex, Jellyfin, or the demo, on iOS or tvOS. It does the following:
  - drops blocked titles from home, library, search, detail, favorites,
    playlists, queues and downloads
  - removes hubs and rows that end up empty, and re-indexes paged listings
  - throws when a blocked title is looked up directly
  - denies server rights, management, playlist edits and subtitle downloads
    unless the parental gate is unlocked
  - replaces Live TV with a service that is never available, and refuses
    external playback
- **The conformance test, `SafeMediaServicesTests`,** checks that a blocked
  item never leaves the wrapper. It also fails when a provider protocol gains
  a requirement that `SafeMediaServices.reviewedRequirements` does not
  classify.

Two details of the rules matter when you work near them. Seasons and episodes
are judged on their own rating and do not inherit the show's. Adult-only means
NC-17, X, XXX and any 18 certificate, and those are rejected even when
unrated content is allowed. Collections, playlists and folders are
containers: they are listed, and their entries are filtered when opened.

### Reviewed requirements

`SafeMediaServices.reviewedRequirements` lists every requirement of every
protocol `MediaServices` is built from, by protocol and selector, with one of
these treatments:

| Treatment | Meaning | Examples |
|---|---|---|
| `filtered` | Returns titles. Every one passes the gate, and a blocked subject throws `ContentSafetyError.blocked` | Home rows, library items and previews, search, detail and seasons, favorites, playlist entries, queues, `prepare`, `prepareDownload` |
| `container` | Returns collections or playlists as they are; their entries are filtered when opened | `collections(in:)`, `playlists(in:)` |
| `gated` | Parent-only: refused, empty or false unless the parental gate is unlocked | Server rights (`authorization`), every management action, playlist edits, subtitle search and install |
| `passthrough` | Returns no titles: writes, reports, settings, or artwork of titles the caller already has | Played state, favorites writes, progress reports, artwork |
| `disabled` | Never reaches the provider | Live TV and DVR, external playback, Plex letter indexes |

When you add a protocol requirement, classify it here. A `filtered`
requirement also needs a probe in `SafeMediaServicesTests` that returns an
allowed and a blocked title.

Later checks catch anything that reaches playback or storage some other way:

- `PlinxPlaybackLauncher` fetches the title again through the boundary and
  requires every queue member to be allowed before it presents anything.
- The player presentation checks the queue and any local file again, and
  closes a Live TV presentation.
- The iOS and tvOS player wrappers check every item at the single load site,
  including autoplay, queue advance and SharePlay. Their
  `isPlaybackAuthorized` defaults to the gate.
- `DownloadManager` checks every item before it enqueues a download, including
  each episode of a season or show.

### Outside the boundary

These paths don't go through `MediaServices`, so each has its own fail-closed
control:

| Path | Control |
|---|---|
| Youtarr Explore | `YoutarrExploreSafetyPolicy`: a video must pass both the Youtarr key's server policy and the local policy. Unknown and adult-only labels are rejected, unrated videos need both policies to allow them, and the kid UI has no external links |
| Downloaded files and the offline store | `DownloadAccessPolicy` checks stored and pinned metadata with the gate. The downloads screens list only the active profile's allowed downloads; other downloads appear only while the parental gate is unlocked and never play from that list. The "downloaded only" library listing checks every item it reads |
| Seerr discovery and requests | Off for kids until the Seerr kid model ships (a Seerr user per kid, certification filtering). `PlinxSettingsSanitizer` disables the discover tab and the Home hero. Trending candidates are only library titles fetched through the boundary, and are checked again |
| Artwork | Passed through: it only draws titles the caller already has |
| Plex account, Home user and server lists | Carry no titles |

A new content source must either go through `MediaServices` or appear in this
table with its own fail-closed control. The
[privacy and safety guide](../security/privacy-and-safety.md) describes the
player, download, profile and sign-out controls in full.

## Home Catalog Loading

Plinx Home draws two sources:

- **Continue Watching** comes from the absorbed `HomeViewModel`, merged across
  every connected server. Next Up items join the end of the same row without
  duplicates. Plinx adopts upstream's load, periodic refresh and
  refresh-after-content-change lifecycle.
- **Recently added** rows come from `HomeRecentlyAddedStore`. It loads each
  visible movie, series and clip library with
  `LibraryCatalogLoader(services:).recentItems(for:limit:)` over that
  server's `MediaServices`, a few libraries at a time; a library that fails is
  left out. When a server becomes ready only its libraries reload, and a
  server's libraries reload after its watch state or media changes. A policy
  change (`ContentSafetyGate.revision`) discards every row and reloads, and
  results that arrive under an old policy are dropped.
  `HomeRecentlyAddedProjection` then applies the movie and TV grouping and
  the parent's Home order and hiding.

Every row is checked with the gate again when it is drawn, so a stricter
policy hides titles at once. Items, the hero selection and tvOS focus memory
are keyed by server plus item ID, because two servers can use the same ID.
Upstream's Home hero carousel is not drawn, and the sanitizer turns it off.

## Features Not Shipped

- **Removed:** Trakt and Simkl sync (no viewing history leaves the device),
  Sentry, the macOS app, and the Top Shelf extension.
- **Off in the kid app:** Live TV and external players
  (`ExternalPlayerApps` always fails).
- **Hidden by default:** SharePlay; `\.sharePlayPresentationPolicy` defaults
  to `.hidden`.
- **Not carried over:** the tvOS system player style and playback-speed
  control. Plinx keeps its own player chrome.

The [hard-fork plan](../maintenance/strimr-hard-fork-plan.md) records the
reasoning and the later phases for Seerr, Live TV and Top Shelf.

## Persisted Identifiers

Keys that came from Strimr keep their names, such as the Keychain item
`strimr.plex.authToken`. Renaming one would sign families out or reset what
they saved. Add a migration if a rename is ever unavoidable.

The Plex product identity reads the app's display name, so requests and the
sign-in page say Plinx.

## Working In The Codebase

1. Put a change where its concept lives. Use `Core/` for shared session,
   provider, model and player behavior, `Platform/` for a platform screen, and
   `Views/` for Plinx presentation. There is no "upstream-owned" layer to
   route around.
2. Enforce content safety at the boundary, not in a screen. If a screen needs
   a filter that `SafeMediaServices` doesn't apply, add it to the boundary and
   its test.
3. New provider protocol requirements need an entry in
   `reviewedRequirements` and, for content, a probe in
   `SafeMediaServicesTests`.
4. Keep kid-facing UI free of external links, social actions and app
   hand-offs. Parent-only tools render only while the parental gate is
   unlocked.
5. Port upstream changes by hand, following the
   [upstream provenance page](../maintenance/upstream-strimr.md). Judge each
   change against kid safety, zero collection and the no-external-links rule
   before you adopt it.
