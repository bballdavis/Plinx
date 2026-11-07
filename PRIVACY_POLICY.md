# Privacy Policy

Effective date: November 7, 2026

Plinx is an independent, parent-managed client for Plex Media Server. This policy explains what the Plinx developer does not collect, what the app stores locally, and when the app communicates with Plex services and servers selected by the user.

## Plinx Developer Collection

The Plinx developer does not operate an analytics, advertising, telemetry, account, or media service. Plinx does not send the developer:

- names, email addresses, account identifiers, or device identifiers;
- viewing history, searches, library contents, or downloaded media;
- crash reports, diagnostics, analytics, or advertising data;
- location, contacts, photos, or microphone data.

Plinx contains no advertising or third-party analytics SDK.

## Plex and User-Selected Servers

Plinx communicates with Plex services to authenticate an existing Plex account, discover available servers and profiles, and request media. It also communicates directly with the Plex Media Server selected by the user, including servers on the local network.

Those communications can include Plex account/profile identifiers, authentication tokens, server identifiers, media metadata, searches, playback requests, progress updates, and download requests. Plex and the server operator process that information under their own policies and configuration. Review the [Plex Privacy Policy](https://www.plex.tv/about/privacy-legal/) and the policies of the server operator.

Plinx is not affiliated with or endorsed by Plex.

## Information Stored on the Device

Plinx stores only information needed to provide app features:

- Plex authentication tokens, connection details, and the parental PIN in the system Keychain;
- content-control, appearance, playback, library, and download preferences in app-local settings;
- downloaded media, artwork, playback progress, and an app-local server/profile ownership record for offline access.

The ownership record prevents a download created under one Plex server/profile from appearing after a different server or profile is selected. Plinx does not upload this record.

## Optional iCloud Settings Sync

A parent can turn on "Sync Settings with iCloud" in protected settings on each device. It is off by default. When it is on, Plinx stores a copy of these preferences in Apple's iCloud key-value storage for the iCloud account signed in on that device: content-rating limits and unrated filtering, touch lock, the Plinx player volume limit, navigation and appearance choices, home-screen and library layout, and library visibility. Other devices using the same iCloud account receive them only when sync is also turned on there.

This data is stored and transmitted by Apple under the [Apple Privacy Policy](https://www.apple.com/legal/privacy/). The Plinx developer operates no server for it and cannot access it. Plinx never syncs the parental PIN, Plex or Youtarr credentials, Youtarr connection details, download settings, downloaded media, or the download ownership record.

Turning sync off stops further syncing and keeps the device's current settings. If the iCloud account on a device changes, Plinx turns sync off on that device until a parent turns it on again.

## Local Network

Plinx requests local-network access so it can find and communicate with Plex Media Servers on the same network. Denying access can prevent local servers from loading; remote Plex connections may still work when available.

## Retention and Deletion

Settings and downloaded files remain on the device until they are changed or deleted. Preferences copied to iCloud by optional settings sync remain in the user's iCloud account under Apple's controls. Signing out removes the stored Plex authentication token and default-server selection, but it does not silently delete downloads. Downloads from a different or unidentified profile are hidden and can be removed from parent-authorized download management.

Uninstalling Plinx removes its app container and downloaded files. The operating system controls Keychain retention; reinstalling may preserve Keychain items unless they are explicitly replaced or the device is erased.

## Children and Families

Plinx is presented as a parent-managed family media client, not as a Kids Category app. The developer does not knowingly collect personal information from children or adults because the developer receives no app data.

## Security

Plinx uses Apple Keychain for sensitive credentials and prefers encrypted Plex connections when available. No method of storage or transmission is guaranteed to be completely secure, particularly when a user-selected Plex server offers only an unencrypted local connection.

## Changes and Contact

Material changes will be reflected in this policy and its effective date. Questions or privacy requests can be submitted through [Plinx Support](https://github.com/bballdavis/Plinx/issues).
