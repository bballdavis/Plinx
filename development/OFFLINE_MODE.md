# Offline Mode And Reconnect

Plinx uses offline mode to fall back to downloaded content when the current Plex session stops being usable. The reconnect path is intentionally centralized so the app does not flip back online just because the OS reports a satisfied network path.

## Ownership

- Effective offline state lives in `DownloadManager.isOffline`.
- `PlinxContentView` is the single reconnect owner.
- Offline child views request reconnect through closures provided by `PlinxContentView`; they do not call `DownloadManager.recheckNetworkStatus()` directly.

## State Contract

`DownloadManager` now treats `NWPathMonitor` as an immediate signal for going offline only.

- If the path becomes unsatisfied, `isOffline` is set to `true` immediately.
- If the path becomes satisfied again, `NWPathMonitor` does not clear `isOffline` by itself.
- The only path that clears offline mode is `recheckNetworkStatus(serverProbe:)`.

This avoids the old failure mode where WiFi returned, the app briefly flipped online, then Plex/session recovery failed and pushed the app back offline again.

## Reconnect Triggers

All reconnect attempts funnel through `PlinxContentView.performReconnect(trigger:)`.

Supported triggers:

1. `manual`: pull-to-refresh or the single empty-state reconnect button on offline screens.
2. `foreground`: app becomes active while already offline.
3. `connectionError`: a live Plex request reports `.plexConnectionUnavailable`.

The reconnect owner serializes these requests with a single in-flight task. If another trigger fires while reconnect is already running, it waits on the same task instead of starting a second recovery attempt.

Manual and foreground reconnects also retry for a short window before giving up. This covers the common case where Wi-Fi has just returned but `NWPathMonitor` has not yet published the satisfied path that same instant.

## Recovery Rules

`performReconnect(trigger:)` calls `DownloadManager.recheckNetworkStatus(serverProbe:)` with a Plinx-owned async probe.

The probe logic is:

1. Verify general Plex reachability with `PlexAPIContext.canReachServer()`.
2. For offline manual and foreground recovery:
   - If `SessionManager.status == .ready`, allow the app back online after the probe succeeds.
   - Otherwise call `SessionManager.hydrate()` before allowing the transition.
3. For connection-error recovery:
   - Re-run `hydrate()` when needed so stale server/session state can be rebuilt.

The ready-session exception is intentional. Plinx's live direct-server reconnect harness can have enough information to reach the server but not enough Plex Cloud state to rebuild the session from `hydrate()` every time. Requiring hydrate as the only reconnect gate would regress that direct reconnect path.

## Non-Ready Online States

A reconnect does not require `SessionManager.status == .ready`.

If the app can reach Plex and `hydrate()` settles in one of these states, Plinx should leave offline mode and show the correct online flow:

- `.signedOut`
- `.needsProfileSelection`
- `.needsServerSelection`
- `.ready`

Offline mode is for unavailable connectivity, not for replacing valid online recovery flows.

## UI Contract

- Pull-to-refresh is the primary reconnect affordance on populated offline screens.
- There should be no more than one visible reconnect button on a page.
- Explicit reconnect buttons are limited to empty states.
- Reconnect buttons use `PlinxReconnectButton`, which matches the app's chrome material/stroke language instead of `.borderedProminent`.

Current offline surfaces:

- Offline home: pull-to-refresh, empty-state button only when there are no offline sections.
- Offline library: pull-to-refresh, empty-state button only when there are no offline libraries.
- Offline library detail: pull-to-refresh only.
- Offline downloads: pull-to-refresh, empty-state button only when there are no downloads.

## Key Files

- `PlinxApp/Views/PlinxContentView.swift`
- `PlinxApp/Views/Offline/OfflineRootView.swift`
- `PlinxApp/Views/Downloads/PlinxDownloadsGridView.swift`
- `PlinxApp/App/ThemeExtensions.swift`
- `../strimr/Strimr-iOS/Features/Downloads/DownloadManager.swift`
- `../strimr/Shared/Networking/Plex/PlexAPIContext.swift`
