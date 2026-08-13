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
| Browse, search, and play approved Plex media | Yes | Yes |
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

Download actions are intentionally absent on Apple TV. Use an iPhone or iPad
when a parent needs to save authorized media for offline playback.

## Troubleshooting

- If a server is missing, confirm the selected Plex account and profile can see
  it, then return to protected settings to choose the server again.
- If focus seems lost, press Menu to dismiss the current sheet and use the
  directional controls to select a visible action. Every primary Apple TV
  action is intended to be reachable by remote navigation.
- If a title is not visible, a parent should check the active rating ceiling
  and library visibility. Plinx applies those rules before display and again
  before playback.
- If Youtarr is not visible, confirm that a parent configured the service and
  that the selected profile and content policy allow eligible videos.
