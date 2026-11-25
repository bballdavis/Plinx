# Privacy And Safety

## Core Policy

Plinx is built around three non-negotiable rules:

- kid safety comes first
- zero collection is the privacy baseline
- kid-facing UI must not expose external links

## Zero-Collection Implementation

Current implementation anchors:

- `PlinxApp/Resources/PrivacyInfo.xcprivacy` declares no tracking or collected data types and declares approved reasons for app-local `UserDefaults` and user-visible disk-space checks
- `PlinxApp/App/ErrorReporter.swift` is a no-op reporter (`isEnabled` is always
  false), so no crash or analytics SDK is active. It is the only reporter in
  the codebase; upstream's Sentry reporter was not carried over
- `PlinxApp/project.yml` links no crash-reporting, analytics, or tracking
  package, and the in-app license list names no such SDK
- Trakt and Simkl sync were removed when Plinx absorbed Strimr, so no viewing
  history leaves the device for a tracking service
- Plinx ships no Top Shelf extension and writes no session credentials for
  one. The upstream write path (`SessionManager.updateTopShelf` and
  `TopShelfSessionStore.save`) is removed, so `TopShelfSessionStore` can only
  clear. Log Out on Apple TV clears any Top Shelf credentials an earlier build
  stored
- the App Review sample library is answered on the device; see
  [Local sample library](#local-sample-library)

Do not add analytics, crash reporting, telemetry, or usage tracking without explicitly changing product policy and documentation first.

## Kid-Safety Boundaries

Safety-critical behavior lives in:

- `Packages/PlinxCore/Sources/PlinxCore/Safety/` and
  `ContentRatingNormalizer`: the rating policy and how ratings are parsed
- `PlinxApp/Core/Safety/`: `ContentSafetyGate` and `SafeMediaServices`, the
  one content boundary every provider goes through
- `ParentalAccessCoordinator`, which stores the parent PIN in Keychain,
  rate-limits PIN attempts, relocks when protected UI closes or the app
  leaves the foreground (`ParentalSceneLock`), and fails closed when Keychain
  is unavailable
- `ContentSafetyBoundary` in `PlinxApp/App/PlinxApp.swift`, which keeps
  `ContentSafetyGate.isParentUnlocked` equal to the effective parental gate
- `PlinxPlaybackLauncher` and the iOS and tvOS player wrappers, which check
  every title again before it plays
- `DownloadManager` and `DownloadAccessPolicy`, which scope offline media to
  the profile that downloaded it

Safety behavior should fail closed whenever possible. If filtering metadata is missing or uncertain, the default should not broaden kid-facing visibility by accident.

All libraries are visible by default, but visibility is independent from content authorization. Default ceilings are G and TV-Y; parents can raise either ceiling in protected settings. Unrated/unknown media—including clips and home videos—is excluded unless a parent opts in.

### The content boundary

`MediaServices.init` passes every provider service through
`SafeMediaServices`. Plex, Jellyfin, and the sample library all build their
services through that initializer, so no unfiltered `MediaServices` exists on
iOS or tvOS. `SafeMediaServices` asks `ContentSafetyGate` about every title:

- **Rating rules.** A title is judged on its own content rating (Plex
  `contentRating`, Jellyfin `OfficialRating` and `CustomRating`) against the
  ceiling for that rating's scale: TV ratings against the TV ceiling, movie
  ratings against the movie ceiling.
- **Seasons and episodes are judged with their series.** A season or episode
  must pass on its own rating and on its series' rating, and one without a
  rating of its own takes the series' rating instead of counting as unrated.
  Servers rarely rate seasons and episodes (Jellyfin almost never), so without
  this every unrated episode of an R or TV-MA series would pass once a parent
  allows unrated content, in Continue Watching, Next Up, search, season pages,
  season downloads, and the playback queue. The boundary looks each series up
  through the provider (unfiltered, once per launch) before it judges its
  seasons and episodes. An unrated season or episode whose series cannot be
  looked up is rejected under every policy; a rated one is then judged on its
  own rating. So a parent who allows unrated content only to see Jellyfin TV
  gets each show's episodes judged by the show's rating.
- **Jellyfin custom ratings.** A Jellyfin admin can give a title a custom
  rating that overrides its official one. Plinx asks for `CustomRating` on
  every item request and judges the stricter of the two
  (`JellyfinContentRating`): an adult-only rating in either one wins; of two
  recognized ratings, the more severe wins; a rating Plinx cannot read never
  replaces one it can. So a custom rating can block a title whose official
  rating is under the ceiling, but cannot unblock one whose recognized
  official rating is over it. The result is the item's `contentRating`, so
  downloads and favorites are judged on it too.
- **Adult-only ratings are always rejected.** NC-17, X, XXX, and any age
  certificate of 18 or older from any country (for example `18`, `R18+`,
  `FSK 18`, `KR-19`, `R21`, `21+`, or `18A`) never pass, even when a parent
  allows unrated content. A rating written with spaces and followed by a note,
  such as `R 21 (SG)` or `PG 13 (US)`, is read as the whole rating.
- **Unrated content passes only with `allowUnrated`.** A missing rating, or
  one the normalizer does not recognize (including other countries' systems),
  counts as unrated.
- **Containers.** Collections, playlists, and folders are listed, and their
  entries are filtered when the container is opened. Collections and playlists
  are listed without the artwork, entry count, and running time their server
  builds from every entry: a Plex composite or a Jellyfin collage would show
  the posters of blocked titles, so their tiles are plain. A container whose
  entries are all blocked is still listed by name and opens empty.
- **Listings.** Blocked titles are dropped from home, library, search, detail,
  favorites, playlists, queues, and downloads, and hubs or rows left empty
  disappear. Paged listings are re-indexed so positions and totals count only
  allowed titles. The Plex letter index is turned off because the server's
  counts include blocked titles. Looking up a blocked title directly throws.
- **Live TV is off.** The provider's Live TV service is replaced by one that
  is never available.
- **Parent-only while locked.** Server rights, every management action (the
  Manage menu), playlist edits, subtitle search and install, and watchlist
  writes are refused unless the parental gate is unlocked. Favorites, played
  state, and removing a title from Continue Watching stay available to kids.
  The screens hide these actions and the boundary refuses them from the same
  flag, `ContentSafetyGate.isParentUnlocked`. `ContentSafetyBoundary` keeps
  that flag equal to the effective parental gate, the sample library's own
  gate included. It observes the coordinator directly rather than waiting for
  a view update: the flag clears the moment an unlocked gate starts to lock,
  and a newly unlocked gate is copied on the next main-actor turn.
- **There is no external playback.** No provider protocol builds a playback
  URL for another app, and the launcher has no option for one.
  `SafeMediaServicesTests` fails if a provider requirement for it comes back.

A policy change bumps the gate's `revision`. Home reloads, and the tab shell
is rebuilt so screens opened under the old policy close. While Settings is
unlocked the rebuild waits until Settings relocks, so editing ratings never
closes Settings. Screens also check titles with the gate again when they draw
rows, results, and detail pages.

### Later checks

Some screens hold titles that were loaded earlier, under an older policy, or
read from the device instead of through the boundary. Each checks them with the
gate again before showing them:

- **Home rows and hero.** `HomeViewModel.rows` filters every row each time it
  is read, including rows restored from the offline cache. The hero re-checks
  every slide (resume and featured) when it is rebuilt, and the saved
  same-day featured selection is filtered before it is reused.
- **My Favorites.** `HomeFavoritesStore` checks every favorite with the gate
  each time the Home row is drawn and drops favorites from libraries the
  profile hides; a favorite that names no library is dropped while the profile
  hides any library of its server. A policy change discards every loaded
  favorite before the reload. Plex favorites are stored on the device with the
  rating the title had when it was added, so this check, the detail page and
  the player all judge it again against the current policy.
- **Search.** `SearchViewModel` first drops results from libraries the profile
  hides (see [Library visibility](#library-visibility)), then checks each title
  with the gate, and only then merges and ranks results across servers.
- **Downloaded library listing.** The "downloaded only" library view reads the
  offline store directly, so every item it lists is filtered by the gate.
- **Offline next episode.** When a downloaded episode ends, the next
  downloaded episode is offered only if `DownloadAccessPolicy` allows it, the
  same decision the downloads grid, the detail page and the launcher make: it
  must belong to the active profile, and both the metadata stored with it and
  the server metadata pinned for it must pass the gate. An episode the
  downloads grid hides never reaches the next-episode card; the chain ends
  there instead.

`SafeMediaServices.reviewedRequirements` classifies every requirement of every
provider protocol, and `SafeMediaServicesTests` fails when a protocol gains a
requirement that is not classified. The
[codebase architecture](../architecture/strimr-integration.md#safety-boundary)
page explains the classification.

### Paths outside the boundary

These content paths don't go through `MediaServices`, so each has its own
fail-closed control:

| Path | Control |
|---|---|
| Youtarr Explore | `YoutarrExploreSafetyPolicy`: a video must pass both the Youtarr key's server policy and the local policy. Unknown and adult-only labels are rejected, and unrated videos show only when both policies allow them. See [Youtarr privacy and safety](youtarr-privacy-and-safety.md) |
| Downloads and the offline store | `DownloadAccessPolicy` checks each download's stored metadata and its pinned media with the gate again. The "downloaded only" library listing checks every item it reads from the offline store. A downloaded season or episode is judged against its series' rating as the gate last learned it; on iOS the gate keeps those ratings in the app's caches (`SeriesRatingStore`: series IDs and rating text, no titles, never sent anywhere), so this works offline. Preparing a download writes its series' rating at once. If the system has purged them, or a download predates them, an unrated downloaded episode stays hidden until Plinx sees its series again online (browsing the show, or any listing that includes its episodes); a rated one is judged on its own rating until then. Log Out leaves them, since they hold no titles and downloads stay on the device |
| Seerr discovery and requests | Off for kids until the Seerr kid model ships (a Seerr user per kid and certification filtering). `PlinxSettingsSanitizer` turns off the discover tab and the Home hero. Trending candidates are only library titles fetched through the boundary, and are checked again |
| Artwork | Passed through: it only draws paths the caller already has, and the boundary hands out no path that draws a blocked title. Collections and playlists lose their server composite, which shows every entry, blocked ones too |
| Plex account, Home user, and server lists | Carry no titles |

A new content source must go through `MediaServices` or be added to this table
with its own fail-closed control.

### Playback

- `PlinxPlaybackLauncher` fetches the starting title again through the
  boundary and checks it with the gate. Every queue member must be allowed,
  or nothing plays. An empty queue, a bad index, or a cancelled launch never
  presents the player. Offline, it plays only the active profile's completed
  downloaded copy from that server, and only if the gate allows both the
  metadata stored with it and the server metadata pinned for it. The
  launcher uses the shared gate, so an unrated season or episode is judged
  against its series' rating as the gate learned it; a caller that must
  check against another policy passes `ContentSafetyGate(policy:)` as the
  launcher's gate. `PlaybackLauncherTests` covers each of these rules.
- Playlist Play and Shuffle start only an entry the shared gate allows at
  that moment, and the launcher checks it again.
- The player presentation checks every queue item, and a local file's media,
  again before it shows the player, and closes a Live TV presentation.
- The iOS and tvOS player wrappers authorize every title at the single load
  site, and again before autoplay, queue advance, or SharePlay loads another
  title. `isPlaybackAuthorized` defaults to the gate. A refused title stops
  playback, leaves any SharePlay session, and closes the player.
- Player output is capped by the parent's maximum volume
  (`maxVolumePercent`, default 70%). The cap applies from the start of
  playback, around every engine load, to volume changes, and to the
  sleep-timer fade. A player that has not received the setting yet plays at
  the 70% default. There is no in-app volume control, so the player plays at
  the cap and follows it when a parent raises or lowers it. It limits only
  the Plinx player and is not hearing protection.
- SharePlay initiation is hidden by default:
  `\.sharePlayPresentationPolicy` defaults to `.hidden`. Media detail on iOS
  and tvOS shows its SharePlay actions only when the policy is `.enabled`, and
  starting a session from detail returns early otherwise. Incoming SharePlay
  playback goes through the same launcher and player checks.
- Playback speed is fixed at 1x. There is no speed control and no stored
  speed setting: `PlayerController` always plays at normal speed, also when it
  continues locally after a SharePlay session.
- External players are never used. Plinx does not hand playback to another
  app, because that would bypass the content checks and the volume cap.
- Subtitle search is parent-only, including automatic search.
  `PlayerViewModel.canSearchSubtitles` requires the parental gate to be
  unlocked, so the player's track menus hide it and automatic search never
  starts while the gate is locked. An automatic search that is running stops
  before it downloads or installs anything if the gate relocks, and the
  boundary refuses the request in any case. The automatic-search setting is
  also hidden and reset to off.
- Picture in Picture and background audio are parent settings and default to
  off.
- Leaving the app closes the player, and it reopens and resumes on return
  (`LifecycleHardeningModifier`). On iPhone and iPad, when a parent has turned
  on Picture in Picture or background audio, `PlayerBackgroundPolicy` keeps
  the player open instead, because closing it would end both: the player keeps
  playing in a Picture in Picture window or as background audio, and
  otherwise pauses (a SharePlay session keeps playing, so that it does not
  pause every participant). The app declares the `audio` background mode only
  so these two settings work. tvOS offers neither setting and always closes
  the player. On iPhone and iPad, a low-memory warning or a change in screen
  capture closes the player whatever the settings.

### Media detail and card actions

These actions are hidden from kids, not just refused, so a locked screen never
offers a button that fails:

- **Playlists.** "Add to playlist" in media detail and card menus, and the
  playlist card's Rename and Delete, show only while the parental gate is
  unlocked. The boundary refuses playlist edits in any case.
- **Watchlist and Shuffle.** Media detail does not offer Watchlist or Shuffle
  to kids. Watchlist writes change the family's Plex account, so the boundary
  also refuses them unless the parental gate is unlocked.
- **SharePlay.** Hidden unless the SharePlay policy is enabled; see
  [Playback](#playback).

### Settings, profiles, and sign-out

- **Settings relock on teardown.** `PlinxSettingsAccessLease` locks the
  parental gate when unlocked Settings leaves the screen without its close
  path: a profile switch, removing an account, changing a profile's
  connections, or Log Out. Each of these rebuilds the root shell, which would
  otherwise leave the gate, and the boundary's parent-only abilities, open.
- **Leaving the app relocks, with one bounded exception.**
  `ParentalSceneLock` locks the parental gate whenever the app leaves the
  foreground, including the inactive phase. Plex sign-in leaves the app: the
  system's sign-in prompt, the Safari fallback, or a switch to a password
  manager, authenticator, or email. Relocking then would replace Settings with
  the gate and cancel the sign-in, so on iPhone and iPad an in-progress Plex
  sign-in (`SignInViewModel`) holds a `ParentalRelockDeferral` lease. While it
  does, the relock waits. It happens as soon as the sign-in ends (succeeds,
  fails, or is cancelled) while the app is still away, or when the app comes
  back after more than five minutes away
  (`ParentalSceneLock.signInGracePeriod`).
  Leases are held weakly, so a sign-in torn down without ending its lease
  stops deferring. The exception covers adding or reconnecting a Plex account
  from Settings and adding a connection from Manage profiles. Apple TV
  (on-screen code) and Jellyfin (in-app form) never leave the app.
- **Profile switching is gated.** Continuing as the last active profile needs
  no gate. Switching to another profile, Manage profiles, adding a connection,
  and Log Out require the parental gate unless Settings already unlocked it,
  and the gate relocks after the action.
- **No remembered profile fails closed.** When no profile is remembered as
  last active (a Plex Home user was removed, or a profile or account was
  deleted), no choice counts as continuing, so every choice on the picker
  needs the parental gate (`PlinxProfileSwitchRules.requiresParentalApproval`).
  Only choosing the Plex Home user during account setup is exempt; the first
  launch remembers its profile before the picker can appear.
- **The gate guards Manage profiles.** The profile picker offers Manage
  profiles whether or not the active Plex profile is restricted
  (`PlinxProfileSwitchRules.showsManageProfiles`), and it always opens behind
  the parental gate. Upstream hid it from restricted Plex profiles instead;
  in Plinx the gate, not the restricted flag, decides who may manage profiles.
- **Profile management never outlives the gate.** On iPhone, iPad, and Apple
  TV, profile management opened from the picker shows the parental gate in
  place of its content whenever the gate is locked, as Settings and Manage
  Downloads do, so the relock when the app leaves the foreground covers it too.
  An approval that would leave protected UI open (`PlinxParentalRequest` with
  `relocksAfterAction == false`) is dropped if the gate relocked before the
  gate screen closed.
- **Log Out from the profile picker is the full sign-out.** On iPhone, iPad,
  and Apple TV, the picker's Log Out runs the same `PlinxSignOut` as Settings,
  described below.
- **No profile re-prompt.** Upstream's 15-minute profile re-prompt is disabled
  (`SessionManager.promptsForProfileOnReturn`), so a child returning to the
  app is never offered the family's other profiles.
- **Settings Plinx hides.** Live TV options, automatic subtitle search, the
  error-report toggle, Integrations and Seerr, and interface settings are not
  offered. The upstream tvOS player style, default playback speed and
  external player choice are deleted rather than hidden: the Apple TV player
  always shows the Plinx controls and timeline, videos always play at normal
  speed in the Plinx player, and a style, speed or external player saved by
  an earlier build is ignored.
- **Log Out** (`PlinxSignOut`) removes every Plex account and Jellyfin server
  and revokes everything on the device that could reach the family's media
  without signing in again:
  1. On iPhone and iPad, it first sends watch progress recorded offline to
     each server.
  2. It removes every account's tokens, profile links, and server choices.
  3. It clears the active download owners, so no download is listed or
     playable until a profile signs in again. Files stay on the device, still
     owned by the profile that made them.
  4. It clears the offline browsing cache of titles and artwork.
  5. It deletes the retired offline-session Keychain item.
  6. On Apple TV, it clears any Top Shelf credentials an earlier build stored.
  7. It locks the parental gate.

### Downloads

Downloads are available on iPhone and iPad only.

- **Ownership.** Each download records its owner (`ownerID`, a `MediaOwner`:
  provider, server, and user). That is the only ownership record, and it is
  stored with the download in the offline database. Only the active profile's
  downloads that the current policy allows are listed or played.
- **One-time migration.** `LegacyDownloadOwnership` reads the per-profile
  record that earlier versions kept in `plinx.downloadOwnership.v1` once, when
  the download index loaded cleanly, and assigns each recorded download to
  that Plex server and profile. Entries in the old download index that carry a
  profile scope keep exactly that owner (`LegacyDownloadIndex`).
  - A scope with an empty server or profile, or one that names a server other
    than the download's, leaves the download unowned. A scoped entry never
    keeps another owner it carries. A damaged entry is dropped on its own, and
    the `plinx.downloadOwnership.v1` import then waits for a complete list.
  - The offline resume points the old index kept move into the owner's
    offline progress, so a partly watched download resumes there. Like other
    offline playback, that progress is later synchronized with the owner's own
    server, most recent wins; it is sent nowhere else. A download with no
    owner keeps its point and records nothing.
  - Only downloads with no owner get one. A download whose stored server
    differs from the recorded server is left alone, and entries with an empty
    server or profile are skipped.
  - The record is removed only after the new owners are saved. If the save
    fails, nothing changes and the record stays for the next launch.
  - **An unreadable record is kept and nothing is assigned.** A record that
    cannot be decoded, is not data, or has an unknown version changes no
    download, and the record stays on the device.
- **Unowned downloads are parent-only.** A download with no owner record
  belongs to no profile. Children never see it. Parents see it, with other
  profiles' downloads and blocked titles, under "Other downloads" in the
  parent-gated Manage Downloads screen, where it can be deleted but never
  played.
  - **Grandfathered downloads are now parent-only.** Earlier versions marked
    downloads made before per-profile ownership as "grandfathered" and showed
    them to every profile, signed in or not, checked only by the content gate.
    One owner per download cannot express "shared", and giving them to one
    profile would be a guess, so they stay unowned. The same holds for
    "unprovenanced" downloads and downloads the record does not name. A child
    who wants one back downloads it again.
  - **Unowned downloads are never adopted.** Upstream gave every unowned
    download on a server to the first profile that connected to it. Plinx
    removed that, so connecting a profile never takes over another profile's
    or an unowned download.
- **Every enqueue is checked.** `DownloadManager` checks the title, and each
  episode of a season or show, with the gate. A blocked title is refused, and
  any server-side transcode it started is cancelled.
- **Integrity.** `DownloadIntegrityValidator` checks the HTTP status, MIME
  type, file size, `Content-Length`, and, for partial responses,
  `Content-Range` before a file becomes playable. A download index that cannot
  be read is never overwritten, and a damaged entry is dropped on its own
  instead of losing the whole list.

### Offline sessions

Plinx's own offline-session coordinator is retired. The session layer
restores servers from cached resources, so downloaded media and offline
progress work through the same services as online playback.

The Keychain item the coordinator used (`plinx.offlineSession.v1`: the Plex
server's machine identifier and the Plex Home user's UUID of the last ready
session, never a token) is read in one case only: the one-time update to
accounts and profiles cannot reach plex.tv (`migrationFailed`) and the device
has no network. That happens when a family first opens the updated app
offline. Then `PlinxContentView` activates that profile alone as the download
owner (`PlinxLegacyOfflineSession`), so the offline Downloads view lists that
profile's own downloads, still checked by `DownloadAccessPolicy` and the
content gate, as pre-fork Plinx did offline. No snapshot, an unreadable one, or
an empty identifier activates no owner, and the recovery card is shown alone.
When the network returns, ownership goes back to the connected services. Once
the update has finished, Plinx deletes the item, and Log Out deletes it too.
The update never creates an account or profile from the item: it names the
profile whose downloads played offline, not the user the saved sign-in belongs
to, and a wrong guess could pair a child's profile with another user's sign-in.
So the update waits for plex.tv instead (`SessionManager`).

At launch Plinx shows its loading screen while it connects, never an offline
warning. The offline Downloads view appears only when the device has no
network or the session is fully offline, and it lists only the active
profile's downloads. With no signed-in profile there is no owner, so
onboarding stays in front.

### Library visibility

Visible libraries are chosen per profile. A hidden library is left out of
Home, Library, and search. A search result with no library (all Jellyfin
results, and Plex items shared one by one) is dropped whenever the profile
hides any library on that server, which fails closed.

Versions before profiles had one hidden-library list for the whole device.
The update keeps it for the whole family (`MultiServerMigration`): it becomes
the family's library settings (`InterfaceSettings.familyLibraries`), which
every profile without settings of its own uses. That includes Plex Home users
that appear after the update, local profiles added later, and an account
signed in again after its token was revoked. A parent's first change to a
profile copies the family's settings into that profile, and only that profile
changes; a profile that then shows every library keeps showing them. When the
update cannot tell which server the list belonged to, the list waits and is
applied to every server of the first Plex server list Plinx receives, before
any of those servers is used. That can hide a library with the same number on
another server, which fails closed and a parent can undo.

Each profile lists a server's libraries with its own sign-in, so a Plex Home
or Jellyfin user restricted to some libraries sees only those. After a
successful load, Plinx forgets the settings of libraries the server no longer
lists only in the active profile's own settings (`LibraryStore`,
`SettingsManager.pruneLibraries`). A load never removes another profile's or
the family's hidden libraries, so a library hidden for an older child stays
hidden after a younger child who cannot see it uses the app. A load that
finishes after the profile changed is dropped, and the current profile's
libraries load again.

## Test and screenshot hooks

The hooks that UI tests and screenshot capture use are compiled into Debug
builds only. In a Release build they do nothing:

- the UI-test screen routes (`PLINX_UI_TEST_SCREEN`) and the harness screens
  they open;
- the live Plex UI-test sign-in (`LivePlexUITestBootstrap`);
- screenshot capture mode (`ReleaseScreenshotCaptureMode`), including its
  network mutation blocker, and the screenshot orientation override;
- the sample library's UI-test auto-start.

Download fixtures replace the real downloads folder, so seeding them
(`DownloadUITestFixtures`) needs both a Debug build and the `--ui-testing`
launch argument; the `downloadsGrid` screen name alone is not enough.

Release builds keep one piece of the sample-library code: at launch, an
interrupted sample session is discarded before the session loads, so its
synthetic token is never sent anywhere. See
[UI testing](../development/ui-testing.md) for the launch arguments.

## Local sample library

The App Review sample library is a temporary Plex account. It starts only when
no account exists, so it never joins or replaces a family's session. It is
added to the real session stores, so it goes through the same server registry
and content boundary as a family account. Its server is marked as not owned,
so no server-management screens appear.

- `DemoMediaServer` listens only on `127.0.0.1` and serves original bundled
  videos and synthetic Plex and Youtarr responses. It never proxies to or
  contacts another host, and sample requests never schedule an external
  video download.
- plex.tv requests that carry the sample account's synthetic token are
  answered on the device. Any other plex.tv path with that token gets a local
  404, so the token never leaves the device. Requests with other tokens, or
  with none, are not touched.
- Leaving the sample library removes the account, clears its offline browsing
  cache, and stops the listener. If the app was closed while the sample was
  running, the account is removed at the next launch. Log Out and account
  removal also remove it.
- Demo rating settings, library visibility, player preferences, and the
  parental PIN use a separate preferences domain and an in-memory PIN store.
  They reset on entry; the demo PIN is 2468. The demo settings also keep Seerr
  and Live TV off.
- Sample downloads persist under the sample account's owner and are
  unavailable to family profiles.

## External Link Policy

- No external links in kid-facing UI.
- Any legal, attribution, or source links belong behind parental gate or settings surfaces.
- AetherEngine is the only in-app playback engine. Plinx does not hand playback
  to an external app because doing so would bypass content checks and the
  playback-level cap.
- Repository docs and release material may link externally; the restriction applies to the app experience.

## Secrets Handling

`test_creds.yaml.example` is the template for local live-test credentials.

Rules:

- keep the real `test_creds.yaml` local only
- never commit Plex tokens, credentials, or account secrets
- avoid logging raw tokens in scripts, tests, or app code
- when adding new live-test credentials, document them in `test_creds.yaml.example`

## Logging Guidance

- do not log auth tokens, passwords, or raw secrets
- prefer aggregate counts, identifiers already visible in the UI, or redacted forms when debugging is necessary
- if a new log touches safety or identity-sensitive data, review it as a privacy change

## Release Validation Expectations

Before release or archive-oriented changes are considered safe, verify:

- `PrivacyInfo.xcprivacy` is included in the app bundle
- Xcode's privacy report covers the app and every embedded executable/framework
- launch resources and asset catalogs are present
- zero-collection behavior is still intact
- the bundle contains no Trakt or Simkl code or strings, and the string catalog
  ships no tracker or error-report copy (the archive validator and
  `BrandingAssetsTests` enforce both)
- relevant safety and branding tests still pass

Use:

```bash
./scripts/tests/validate_testflight_archive.sh ./build/Plinx.xcarchive
```

## Minimum Tests For Sensitive Changes

| Change area | Minimum tests |
|---|---|
| Safety filtering, rating logic, parental gate | `PlinxCore` tests plus relevant app unit tests |
| Provider protocols, providers, `ContentSafetyGate`, or `SafeMediaServices` | `SafeMediaServicesTests` plus `PlinxCore` tests |
| Download ownership, download access, or the download index | `OfflinePlaybackTests`, `OfflineEpisodeChainingTests` and `DownloadOwnershipMigrationTests` |
| `PlinxPlaybackLauncher`, playback queues, or a playback entry point | `PlaybackLauncherTests` plus `SafeMediaServicesTests` |
| Branding or kid-facing safety surfaces | Branding tests plus snapshot/UI coverage |
| Logging, privacy manifest, reporter, or secret flow | App/unit tests touched by the change plus archive validation when packaging is affected |
| Real-data filtering behavior | live smoke and/or live parity checks when applicable |
