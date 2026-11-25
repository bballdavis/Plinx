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
| `migrationFailed` | Plinx connection recovery; offline on iPhone and iPad, over the Downloads of the profile pre-fork Plinx last signed in (`PlinxLegacyOfflineSession`) |
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
  settings and `ParentalAccessCoordinator` through `ContentSafetyBoundary`.
  The boundary observes the effective coordinator (the family's, or the
  sample library's) directly and clears the unlock flag the moment it starts
  to lock; `ContentSafetyBoundaryTests` covers it. The gate judges a title on
  its own content rating against the ceiling for that rating's scale. A missing or
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
  - replaces Live TV with a service that is never available
  - has no external playback to refuse: no provider protocol builds a URL
    for another app's player
- **The conformance test, `SafeMediaServicesTests`,** checks that a blocked
  item never leaves the wrapper, including through the offline caches, and
  that every parent-only requirement is refused while the gate is locked. It
  also fails when a provider protocol, an offline cache protocol, or a
  service `MediaServices` stores gains a requirement that
  `SafeMediaServices.reviewedRequirements` does not classify.

A few details of the rules matter when you work near them. Seasons and
episodes are judged against their series as well: both their own rating and
the series' rating must pass, and one without a rating of its own takes the
series' rating instead of counting as unrated. Servers rarely rate seasons
and episodes (Jellyfin almost never), so judging them alone would let every
unrated episode of an R or TV-MA series through once a parent allows unrated
content. Each wrapper calls `ContentSafetyGate.learnSeries` with what the
provider returned before filtering it; the gate keeps the rating of every
series it sees and looks up, through the provider's own unfiltered
`mediaItem(id:)`, each series it has not confirmed since launch. An unrated
season or episode whose series cannot be looked up is rejected under every
policy; a rated one is then judged on its own rating. On iOS the gate keeps
the learned ratings in the app's caches (`SeriesRatingStore`: series IDs and
rating text, no titles), so downloaded episodes are judged against their
series offline too. Adult-only means
NC-17, X, XXX and any age certificate of 18 or older (18, KR-19, R21, 21+,
18A), and those are rejected even when unrated content is allowed.
Collections, playlists and folders are containers: they are listed, and their
entries are filtered when opened. Collections and playlists are listed
without the artwork and counts their server builds from every entry
(`ContentSafetyGate.shown(_:)`): a Plex composite or Jellyfin collage draws
the posters of blocked entries too, so their tiles are plain. A container
whose entries are all blocked is still listed by name and opens empty. A
Jellyfin item's rating is the stricter of
its `OfficialRating` and the admin's `CustomRating`, resolved by
`JellyfinContentRating` in the Jellyfin mapping. Jellyfin returns
`CustomRating` only when `Fields` asks for it, so every item request in
`JellyfinCatalogService` carries it through `cardFields` or `queueFields`; a
new item request must too.

### Reviewed requirements

`SafeMediaServices.reviewedRequirements` lists every requirement of every
protocol `MediaServices` is built from or stores (`accountPreferences`), and
of the iOS offline caches the home and detail wrappers expose
(`OfflineHomeCacheReading`, `OfflineDetailCacheReading`), by protocol and
selector, with one of these treatments:

| Treatment | Meaning | Examples |
|---|---|---|
| `filtered` | Returns titles. Every one passes the gate, and a blocked subject throws `ContentSafetyError.blocked` | Home rows, library items and previews, search, detail and seasons, favorites, playlist entries, queues, `prepare`, `prepareDownload` |
| `container` | Returns collections or playlists without their server artwork and counts; their entries are filtered when opened | `collections(in:)`, `playlists(in:)` |
| `gated` | Parent-only: refused, empty or false unless the parental gate is unlocked | Server rights (`authorization`), every management action, playlist edits, subtitle search and install, watchlist writes |
| `passthrough` | Returns no titles: writes, reports, settings, or artwork of paths the caller already has | Played state, favorites writes, progress reports, artwork |
| `disabled` | Never reaches the provider | Live TV and DVR, Plex letter indexes |

When you add a protocol requirement, classify it here. A `filtered`
requirement also needs a probe in `SafeMediaServicesTests` that returns an
allowed and a blocked title, and a `gated` one a probe that the locked gate
must refuse. A service stored on `MediaServices` must be declared as a
reviewed protocol.

Plex and Jellyfin titles are judged only by `ContentSafetyGate`. Code that
must judge them against a policy other than the parent's current one builds a
`ContentSafetyGate(policy:)` rather than applying PlinxCore's rating rules
itself. Such a gate knows no series ratings until it learns them, so it
rejects every unrated season or episode.

Later checks catch anything that reaches playback or storage some other way:

- `PlinxPlaybackLauncher` fetches the title again through the boundary and
  requires every queue member to be allowed by its gate (the shared gate)
  before it presents anything.
- The player presentation checks the queue and any local file again, and
  closes a Live TV presentation.
- The iOS and tvOS player wrappers check every item at the single load site,
  including autoplay, queue advance and SharePlay. Their
  `isPlaybackAuthorized` defaults to the gate.
- `DownloadManager` checks every item before it enqueues a download, including
  each episode of a season or show.
- Screens that hold titles loaded earlier or read from the device check them
  with the gate again: Home rows and the hero (including the saved same-day
  featured selection), search results (after dropping hidden libraries), the
  "downloaded only" library listing, and offline next-episode chaining. The
  [privacy and safety guide](../security/privacy-and-safety.md#later-checks)
  lists them.

### Outside the boundary

These paths don't go through `MediaServices`, so each has its own fail-closed
control:

| Path | Control |
|---|---|
| Youtarr Explore | `YoutarrExploreSafetyPolicy`: a video must pass both the Youtarr key's server policy and the local policy. Unknown and adult-only labels are rejected, unrated videos need both policies to allow them, and the kid UI has no external links |
| Downloaded files and the offline store | `DownloadAccessPolicy` checks stored and pinned metadata with the gate. The downloads screens list only the active profile's allowed downloads; other downloads appear only while the parental gate is unlocked and never play from that list. The "downloaded only" library listing checks every item it reads |
| Seerr discovery and requests | Off for kids until the Seerr kid model ships (a Seerr user per kid, certification filtering). `PlinxSettingsSanitizer` disables the discover tab and the Home hero. Trending candidates are only library titles fetched through the boundary, and are checked again |
| Artwork | Passed through: it only draws paths the caller already has, and the boundary hands out no path that draws a blocked title. Collections and playlists lose their server composite, which shows every entry (blocked ones too), and draw a plain tile |
| Plex account, Home user and server lists | Carry no titles |

A new content source must either go through `MediaServices` or appear in this
table with its own fail-closed control. The
[privacy and safety guide](../security/privacy-and-safety.md) describes the
player, download, profile and sign-out controls in full.

## Home Catalog Loading

Plinx Home draws three sources:

- **Continue Watching** comes from the absorbed `HomeViewModel`, merged across
  every connected server. Next Up items join the end of the same row without
  duplicates. Plinx adopts upstream's load, periodic refresh and
  refresh-after-content-change lifecycle.
- **My Favorites** comes from `HomeFavoritesStore`
  (`Core/Features/Favorites`). It asks every ready server that supports
  favorites through its `MediaServices`, so `SafeFavoritesService` filters the
  list first. Plex favorites are kept on the device for each profile
  (`FavoritesStore`, with the rating the title had when it was added); Jellyfin
  favorites belong to the Jellyfin user. The row reloads when a server becomes
  ready, when a server's watch state changes (adding or removing a favorite
  bumps it), and on pull to refresh, never during playback. A policy change
  discards everything loaded under the old policy, even when the reload fails.
  When drawn, the row keeps only movies, shows, seasons and episodes from the
  profile's enabled servers that the gate allows and that come from a library
  the profile shows. A favorite that names no library (Jellyfin) is left out
  while the profile hides any library of its server, as in search. Titles are
  listed by title, with a show's seasons and episodes after it; the row is
  hidden when empty. Upstream's Favorites tab screen was not kept.
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

### Home library settings

The parent's Home choices are stored in `UserDefaults` under
`plinx.homeHiddenLibraryIds` (libraries hidden from Home) and
`plinx.homeLibraryOrder` (their order). Each value is a
`LibraryIdentity.stableKey` (`<provider>:<serverID>:<libraryID>`), so two
servers that use the same library ID never share a setting.

Builds before multi-server stored the plain library ID. `HomeLibrarySettingKeys`
migrates those values when libraries load:

- The migration waits until every enabled server's libraries have loaded, so
  an ID is never matched while another server is still missing.
- A plain ID that exactly one library has becomes that library's stable key.
  Duplicates are dropped and the order is kept.
- A plain ID that several libraries share, or none, is kept as stored rather
  than guessed.

`HomeRecentlyAddedProjection` reads both forms, so nothing a family set is
lost either way. Turning a library back on removes its stable key; when an
ambiguous plain ID was hiding it, that ID is replaced by the stable keys of
the other libraries that share it, so they stay hidden. Library visibility
(`Visible Libraries`) is a separate, per-profile setting and always wins: a
hidden library is left out of Home whatever these keys say.

## Features Not Shipped

- **Removed:** Trakt and Simkl sync (no viewing history leaves the device),
  Sentry, the macOS app, and the Top Shelf extension.
- **Removed:** external players. Playback never leaves the Plinx player:
  `PlaybackLauncher` has no external-player option, no provider protocol
  builds a direct, token-carrying URL for another app, and an external player
  saved by an earlier build is not read. `SafeMediaServicesTests` fails if a
  provider requirement for external playback comes back.
- **Off in the kid app:** Live TV.
- **Hidden by default:** SharePlay; `\.sharePlayPresentationPolicy` defaults
  to `.hidden`.
- **Not carried over:** the tvOS system player style and playback-speed
  control. The system style's controls, menus and timeline, and the
  `playerControlsStyle` setting, are deleted: the tvOS player has one chrome
  (`PlayerControlsView`) and one timeline (`PlinxPlayerTimelineView`). A
  style saved by an earlier build is ignored when settings load and dropped
  on the next save. Speed control is deleted the same way: there is no speed
  picker, speed settings sheet, rate state in the player views, or
  `defaultPlaybackRate` setting. `PlayerController` plays at a fixed normal
  rate, including when it continues locally after a SharePlay session ends,
  and the "ends at" time assumes normal speed. A default speed saved by an
  earlier build is ignored when settings load and dropped on the next save.

The [hard-fork plan](../maintenance/strimr-hard-fork-plan.md) records the
reasoning and the later phases for Seerr, Live TV and Top Shelf.

### Dormant on purpose

Some upstream code compiles but is never reachable by a child. It is kept on
purpose for planned work, so don't delete it as dead code, and don't wire it
into a screen without that work and a privacy and safety review.

| Area | Where | Why it is inert | Kept for |
|---|---|---|---|
| Seerr discovery and requests | `Core/Features/Seerr`, `SeerrStore` | Seerr view models build their own repositories and don't go through `MediaServices`. `PlinxSettingsSanitizer` turns off the discover tab and the Home hero, and the Seerr settings are hidden, so no kid screen opens them | The Seerr-in-Discover work: a `SeerrCatalogService` protocol behind the safety boundary, a Seerr user per kid, and certification filtering |
| Live TV and DVR | `Core/Features/LiveTV` and each provider's Live TV service | `SafeMediaServices` replaces every provider's `liveTV` with `DisabledLiveTVService`, which is never available, so these screens can't load a channel. The player presentation also closes a Live TV presentation | A parent-approved channel allowlist. Program and channel models carry no rating, so per-item filtering can't fail closed |

### Sample library and screenshots

There is one sample-library mechanism: the App Review sample library in
`App/` (`DemoFixtureBootstrap` with the loopback `DemoMediaServer`). It runs
as a temporary account through the real session stores, server registry and
safety boundary. UI tests and screenshot capture enter that same sample
library; upstream's separate demo and screenshot mode was not kept. The
[privacy and safety guide](../security/privacy-and-safety.md#local-sample-library)
describes its guarantees, and
[testing](../development/testing.md#app-review-demo-fixtures) how tests use it.

## Persisted Identifiers

Keys that came from Strimr keep their names, such as the Keychain item
`strimr.plex.authToken`. Renaming one would sign families out or reset what
they saved. Add a migration if a rename is ever unavoidable. Plinx's own keys
follow the same rule; for example the Home library settings keep their names
and gained a value migration instead (see
[Home library settings](#home-library-settings)).

The same goes for the other identifiers stored on the device: the Keychain
service fallback, the Top Shelf App Group and Keychain service, the background
download session identifier, the `strimr-download://` artwork prefix in saved
download metadata, and the trickplay cache folder. Everything else says Plinx:
type names (for example `PlinxProfile` and `PlinxWatchActivity`), user-visible
text, error domains, and log subsystems. Users see Strimr's name only where
the about and licenses screens credit it.

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
