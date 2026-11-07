# Privacy And Safety

## Core Policy

Plinx is built around three non-negotiable rules:

- kid safety comes first
- zero collection is the privacy baseline
- kid-facing UI must not expose external links

## Zero-Collection Implementation

Current implementation anchors:

- `PlinxApp/Resources/PrivacyInfo.xcprivacy` declares no tracking or collected data types (optional iCloud settings sync stores data in the user's own iCloud account and is not developer collection) and declares approved reasons for app-local `UserDefaults` and user-visible disk-space checks
- `PlinxApp/App/ErrorReporter.swift` is a no-op reporter so no crash or analytics SDK is active
- `PlinxApp/project.yml` excludes Strimr's reporting implementation and wires in the no-op replacement
- the resolved Plinx package graph excludes Sentry even though upstream Strimr
  can use it in its own standalone targets

Do not add analytics, crash reporting, telemetry, or usage tracking without explicitly changing product policy and documentation first.

## Optional iCloud Settings Sync

`PlinxCloudSettingsSync` (`PlinxApp/App/Sync/`) can copy family preferences
through Apple's iCloud key-value store (`NSUbiquitousKeyValueStore`). It does
not change the zero-collection baseline: values stay in the family's own iCloud
account, and Plinx operates no server and never receives them. The privacy
manifest still declares no collected data types.

Rules:

- Sync is off by default and is enabled per device in protected settings.
  Families often share one Apple ID across children who need different limits,
  so enabling it on one device never enables it on another.
- `PlinxSyncedSettingsCatalog` is the allow-list of synced preferences. The
  parent PIN, Plex and Youtarr credentials, the Youtarr connection, download
  quality and Wi-Fi rules, download ownership, device-size layout tuning, and
  the sync switch itself must never be added to it. Unit tests guard this.
- Every incoming value is validated against the choices the UI offers (rating
  allow-lists, accent and button-size cases, volume range, identifier list
  shape and size). Invalid values are ignored and the local value stays.
- A value a device has never set is not uploaded, and nothing is deleted from
  iCloud, so a new device cannot reset another device's choices.
- Turning sync on adopts settings already in iCloud and uploads settings iCloud
  lacks. If iCloud has not delivered anything yet, uploads wait for its first
  download, or for 60 seconds or the next launch with nothing arriving, so a
  new device cannot replace the family's values with its defaults. Later
  changes are last-writer-wins per setting.
- An iCloud account change turns sync off on that device and tells the parent,
  so another account's settings never apply silently. The account identity is
  recorded when sync is turned on and checked at launch before any value is
  applied, so a change made while Plinx was closed is also caught.

Both app targets use the same key-value store identifier
(`$(TeamIdentifierPrefix)com.bballdavis.plinx`), so iPhone, iPad, and Apple TV
share one store. The App ID must have the iCloud capability with key-value
storage enabled.

## Kid-Safety Boundaries

Safety-critical behavior lives primarily in:

- `Packages/PlinxCore/Sources/PlinxCore/Safety/`
- `ParentalAccessCoordinator`, which stores the parent PIN in Keychain,
  rate-limits PIN attempts, relocks when protected UI closes or the app
  backgrounds, and fails closed when Keychain is unavailable
- Plinx adapters/decorators that filter or reshape upstream content before display
- `PlinxPlaybackLauncher`, which refetches current metadata and rechecks every
  play-queue member before local or SharePlay-initiated playback is presented
- `DownloadOwnershipStore`, which keeps offline media scoped to the Plex server/profile that created it

Strimr view models expose item/hub filters, but Plinx supplies the policies.
Incoming SharePlay activity uses the same launcher boundary, and kid-facing
SharePlay initiation controls are hidden through an environment policy.

Safety behavior should fail closed whenever possible. If filtering metadata is missing or uncertain, the default should not broaden kid-facing visibility by accident.

All libraries are visible by default, but visibility is independent from content authorization. Default ceilings are G and TV-Y; parents can raise either ceiling in protected settings. Unrated/unknown media—including clips and home videos—is excluded unless a parent opts in.

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
| Branding or kid-facing safety surfaces | Branding tests plus snapshot/UI coverage |
| Logging, privacy manifest, reporter, or secret flow | App/unit tests touched by the change plus archive validation when packaging is affected |
| Real-data filtering behavior | live smoke and/or live parity checks when applicable |
