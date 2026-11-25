---
sidebar_position: 6
---

# Apple TV guide

Plinx 2026.08 supports streaming on Apple TV. Sign in and choose a server and
profile through the parent-managed setup flow before handing the remote to a
child.

## What works on Apple TV

| Task | Apple TV | iPhone and iPad |
|---|---|---|
| Browse, search, and play approved Plex or Jellyfin media | Yes | Yes |
| Parent gate, rating limits, and library visibility | Yes | Yes |
| Optional parent-configured Youtarr Explore | Yes | Yes |
| Download and offline playback | No | Yes |

Youtarr remains optional and parent-configured. Apple TV never opens external
YouTube links from a kid-facing surface.

## Use the Siri Remote

Use Up, Down, Left, and Right to move the visible focus ring. Press Select to
open the focused item or activate a control. Press Menu to dismiss a sheet or
return to the previous level. Settings remain behind the parental gate; unlock
them before changing profiles, servers, ratings, or library visibility.

Press and hold Select on a media card to open Quick Actions without also
opening or playing the card. The menu can mark playable media watched or
unwatched and open More Info. Library Recommended, Browse, and Collections use
the same interaction as Home, Search, Collection, and Playlist screens.

On a More Info page, use the watched-state button beside Play and Restart.
During playback, hold Select anywhere on the player surface to mark the current
title watched or open More Info. Opening More Info dismisses the player first
and then opens the detail page. Press Menu or Cancel to dismiss Quick Actions.

Download actions are intentionally absent on Apple TV. Use an iPhone or iPad
when a parent needs to save authorized media for offline playback.
While a saved account reconnects, Apple TV shows loading and offers Retry if
the connection fails. The browsing tabs appear when streaming is ready;
Downloads does not appear.

## When the media server can't be reached

If none of the profile's servers can be reached, Apple TV shows a
**Connection unavailable** card in place of the browsing tabs: "Plinx can't
reach your media server. Make sure it's turned on, then try again." Choose
**Try Again** to reconnect; Plinx waits a few seconds for a server to answer
and returns to the tabs as soon as one does. If the Apple TV itself has no
network, the card asks you to connect first.

The card does not appear while Plinx is still connecting. The Plinx header,
Settings, and Explore (when a parent set up Youtarr) stay available while it
is shown.

## Troubleshooting

- If a server is missing, confirm the selected Plex account and profile can see
  it (or that the Jellyfin server and user are correct), then open **Accounts
  and servers** in protected settings to reconnect or choose it again.
- If the **Connection unavailable** card stays up, make sure the media server
  is turned on and reachable from the Apple TV's network, then choose **Try
  Again**.
- If focus seems lost, press Menu to dismiss the current sheet and use the
  directional controls to select a visible action. Every primary Apple TV
  action is intended to be reachable by remote navigation.
- If a title is not visible, a parent should check the active rating ceiling
  and library visibility. Plinx applies those rules before display and again
  before playback.
- If Youtarr is not visible, confirm that a parent configured the service and
  that the selected profile and content policy allow eligible videos.
