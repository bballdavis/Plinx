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
  one. Log Out on Apple TV clears any Top Shelf credentials an earlier build
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
  backgrounds, and fails closed when Keychain is unavailable
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
  `contentRating`, Jellyfin `OfficialRating`) against the ceiling for that
  rating's scale: TV ratings against the TV ceiling, movie ratings against the
  movie ceiling. Seasons and episodes use their own rating; they do not
  inherit the show's.
- **Adult-only ratings are always rejected.** NC-17, X, XXX, and any 18
  certificate never pass, even when a parent allows unrated content.
- **Unrated content passes only with `allowUnrated`.** A missing rating, or
  one the normalizer does not recognize (including other countries' systems),
  counts as unrated.
- **Containers.** Collections, playlists, and folders are listed as they are;
  their entries are filtered when the container is opened.
- **Listings.** Blocked titles are dropped from home, library, search, detail,
  favorites, playlists, queues, and downloads, and hubs or rows left empty
  disappear. Paged listings are re-indexed so positions and totals count only
  allowed titles. The Plex letter index is turned off because the server's
  counts include blocked titles. Looking up a blocked title directly throws.
- **Live TV is off.** The provider's Live TV service is replaced by one that
  is never available.
- **Parent-only while locked.** Server rights, every management action (the
  Manage menu), playlist edits, and subtitle search and install are refused
  unless the parental gate is unlocked. Favorites, watchlist, played state,
  and removing a title from Continue Watching stay available to kids.
- **External playback is refused.** The boundary never returns an external
  playback target.

A policy change bumps the gate's `revision`. Home reloads, and the tab shell
is rebuilt so screens opened under the old policy close. While Settings is
unlocked the rebuild waits until Settings relocks, so editing ratings never
closes Settings. Screens also check titles with the gate again when they draw
rows, results, and detail pages.

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
| Downloads and the offline store | `DownloadAccessPolicy` checks each download's stored metadata and its pinned media with the gate again. The "downloaded only" library listing checks every item it reads from the offline store |
| Seerr discovery and requests | Off for kids until the Seerr kid model ships (a Seerr user per kid and certification filtering). `PlinxSettingsSanitizer` turns off the discover tab and the Home hero. Trending candidates are only library titles fetched through the boundary, and are checked again |
| Artwork | Passed through: it only draws titles the caller already has |
| Plex account, Home user, and server lists | Carry no titles |

A new content source must go through `MediaServices` or be added to this table
with its own fail-closed control.

### Playback

- `PlinxPlaybackLauncher` fetches the starting title again through the
  boundary and checks it with the gate, plus the caller's policy when one is
  given. Every queue member must be allowed, or nothing plays. An empty queue,
  a bad index, or a cancelled launch never presents the player. Offline, it
  plays only the active profile's downloaded copy, and only if the gate
  allows it.
- The player presentation checks every queue item, and a local file's media,
  again before it shows the player, and closes a Live TV presentation.
- The iOS and tvOS player wrappers authorize every title at the single load
  site, and again before autoplay, queue advance, or SharePlay loads another
  title. `isPlaybackAuthorized` defaults to the gate. A refused title stops
  playback, leaves any SharePlay session, and closes the player.
- Player output is capped by the parent's maximum volume
  (`maxVolumePercent`, default 70%). The cap applies from the start of
  playback, around every engine load, to volume changes, and to the
  sleep-timer fade. It limits only the Plinx player and is not hearing
  protection.
- SharePlay initiation is hidden by default:
  `\.sharePlayPresentationPolicy` defaults to `.hidden`. Incoming SharePlay
  playback goes through the same launcher and player checks.
- Playback speed is fixed at 1x. There is no speed control.
- External players are never used. Plinx does not hand playback to another
  app, because that would bypass the content checks and the volume cap.
- Subtitle search is parent-only: it is hidden from the player's track menus
  unless the parental gate is unlocked, and the boundary refuses it.
- Picture in Picture and background audio are parent settings and default to
  off.

### Settings, profiles, and sign-out

- **Settings relock on teardown.** `PlinxSettingsAccessLease` locks the
  parental gate when unlocked Settings leaves the screen without its close
  path: a profile switch, removing an account, changing a profile's
  connections, or Log Out. Each of these rebuilds the root shell, which would
  otherwise leave the gate, and the boundary's parent-only abilities, open.
- **Profile switching is gated.** Continuing as the last active profile needs
  no gate. Switching to another profile, Manage profiles, adding a connection,
  and Log Out require the parental gate unless Settings already unlocked it,
  and the gate relocks after the action.
- **No profile re-prompt.** Upstream's 15-minute profile re-prompt is disabled
  (`SessionManager.promptsForProfileOnReturn`), so a child returning to the
  app is never offered the family's other profiles.
- **Settings Plinx hides.** Default playback speed, external and custom
  external players, the tvOS player style, Live TV options, automatic subtitle
  search, the error-report toggle, Integrations and Seerr, and interface
  settings are not offered.
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
- **One-time migration.** Plinx reads the per-profile records that earlier
  versions kept in `plinx.downloadOwnership.v1` once, and assigns each
  recorded download to that server and profile. Entries in the old download
  index that carry a profile scope keep exactly that owner.
- **Unowned downloads are parent-only.** A download with no owner record,
  such as one made before per-profile ownership, belongs to no profile.
  Children never see it. Parents see it, with other profiles' downloads and
  blocked titles, under "Other downloads" in the parent-gated Manage Downloads
  screen, where it can be deleted but never played.
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
progress work through the same services as online playback. The Keychain item
the coordinator used (`plinx.offlineSession.v1`) is no longer read, and Log
Out deletes it.

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
| Download ownership or the download index | `OfflinePlaybackTests` and `DownloadOwnershipMigrationTests` |
| Branding or kid-facing safety surfaces | Branding tests plus snapshot/UI coverage |
| Logging, privacy manifest, reporter, or secret flow | App/unit tests touched by the change plus archive validation when packaging is affected |
| Real-data filtering behavior | live smoke and/or live parity checks when applicable |
