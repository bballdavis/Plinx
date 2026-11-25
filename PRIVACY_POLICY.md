# Privacy Policy

Effective date: November 24, 2026

Plinx is an independent, parent-managed client for Plex Media Server and Jellyfin servers, with an optional connection to a parent-configured Youtarr service. This policy explains what the Plinx developer does not collect, what the app stores locally, and when the app communicates with services selected by the user.

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

## Jellyfin Servers

A parent can connect one or more Jellyfin servers. Plinx communicates directly with each Jellyfin server the family connects to sign in, list libraries and users, and request media. To find servers, Plinx can send a discovery request on the local network; a parent can also enter a server address.

Those communications can include the Jellyfin username and password entered at sign-in, or a Quick Connect code; the access token the server issues; the app name, device name, and a device identifier; media metadata, searches, playback requests, progress updates, and download requests. Plinx sends the password only to the selected server and does not store it. The Jellyfin server operator processes that information under the server's own configuration and policies.

Plinx is not affiliated with or endorsed by Plex or Jellyfin.

## Optional Youtarr Service

A parent can configure a separate Youtarr service in the protected Settings area. When enabled, Plinx communicates directly with that parent-selected service to load its catalog, metadata, and artwork and to submit requests chosen in the app. Those communications can include the configured service address, API key or additional authorization header, catalog queries, media identifiers, and request details.

The Youtarr operator processes that information under the operator's own configuration and policies. Plinx does not route the communication through the Plinx developer and does not provide or operate a Youtarr service.

## Information Stored on the Device

Plinx stores only information needed to provide app features:

- Plex account and profile tokens, Jellyfin access tokens, Youtarr API credentials or additional authorization header, and the parental PIN in the system Keychain;
- the connected Plex accounts, Jellyfin servers, profiles, and optional Youtarr connection details in app-local settings;
- content-control, appearance, playback, library, and download preferences in app-local settings;
- downloaded media, artwork, playback progress, a cache of titles and artwork for offline browsing, and an app-local ownership record for each download.

The ownership record names the provider (Plex or Jellyfin), the server, and the user that created each download. A download appears only while that same provider, server, and user is active; a download with no owner is visible only from parent-authorized download management. Plinx does not upload this record.

## Local Network

Plinx requests local-network access so it can find and communicate with Plex Media Servers, Jellyfin servers, and an optional parent-configured Youtarr service on the same network. Denying access can prevent local services from loading; remote connections may still work when available.

## Retention and Deletion

Settings and downloaded files remain on the device until they are changed or deleted. Signing out removes every connected account and its stored credentials from the device: Plex account and profile tokens, Jellyfin access tokens, and the linked profiles and server choices. It also clears the offline browsing cache. Before removing the accounts, it sends any watch progress recorded offline to the servers that can still be reached. Signing out does not silently delete downloads or the separately parent-configured Youtarr connection. Downloads stay on the device, owned by the provider, server, and user that created them, and are hidden until that user signs in again; a parent can remove them from parent-authorized download management. A parent can remove or replace the Youtarr configuration from protected Settings.

Uninstalling Plinx removes its app container and downloaded files. The operating system controls Keychain retention; reinstalling may preserve Keychain items unless they are explicitly replaced or the device is erased.

## Children and Families

Plinx is presented as a parent-managed family media client, not as a Kids Category app. The developer does not knowingly collect personal information from children or adults because the developer receives no app data.

## Security

Plinx uses Apple Keychain for sensitive credentials and prefers encrypted Plex connections when available. No method of storage or transmission is guaranteed to be completely secure, particularly when a user-selected Plex or Jellyfin server offers only an unencrypted connection.

## Changes and Contact

Material changes will be reflected in this policy and its effective date. Questions or privacy requests can be submitted through [Plinx Support](https://github.com/bballdavis/Plinx/issues).
