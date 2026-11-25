---
sidebar_position: 4
---

# Using Plinx

For a quick cross-device feature overview, see the [product tour](product-tour.md).

## Where media comes from

Plinx plays media from the family's own servers: Plex Media Servers reached
through a Plex account, and Jellyfin servers. A parent connects them during
setup or later under **Accounts and servers** in protected settings. Each
profile can use several servers at once; Home, Library and Search combine
them.

## Home and libraries

**Continue Watching** combines in-progress titles from every connected
server, with the next episodes of shows you are watching at the end of the
same row. Recently added rows load from the same library catalogs used by
Library Browse. Parents can select which libraries appear and how home
sections are arranged. Movie and TV libraries can be combined or split, while
YouTube and other none-agent video libraries remain separate landscape rows.
If one library is temporarily unavailable, other Home rows can still load.
If a pull-to-refresh cannot reach the server, Home keeps the rows that were
already on screen instead of replacing them with a disconnected state.

Open Libraries to browse an individual library, its recommendations,
collections, and full grids. The available sections reflect the current parent
controls. A library's Recommended tab adds a **Recently Added** row only when
the server returns no other allowed recommendations for that library.

Collections are hidden by default for new installations. Parents can enable
them in Settings; an existing saved preference is preserved.

Visible libraries are chosen separately for each profile. A library a parent
hides for a profile disappears from that profile's Home, Library, and Search.

## Search

Search looks across every connected server. Results are filtered by the same
rating and visibility rules used throughout Plinx, so a blocked item does not
become discoverable just because it matches a search term. Results from a
library hidden for the current profile are left out. When the same title is on
more than one server, Plinx opens the best allowed copy without asking.

## Playback

Choose an item to view its details, resume progress, select an episode, or
start playback. Plinx supports the audio tracks, subtitles, chapters, and
playback resume that the server provides.

Before a play queue is shown, Plinx fetches current metadata and re-applies
the active content policy. This protects direct actions, playlist playback,
autoplay of the next episode, and supported SharePlay-initiated playback
paths. Playback always runs at normal speed and always plays inside Plinx.

The player overlay keeps high-contrast rewind, play or pause, and fast-forward
controls centered over video; they scale up responsively on larger layouts.
The back control and the video title are large for easier reading and
targeting without adding a second persistent back button or rating chip over
the video.

On iPhone and iPad, the player header offers:

- **Tracks**, for audio tracks and subtitles;
- **More Actions**, for marking a video watched or opening its details;
- **Settings**, for playback options and the sleep timer;
- **Fit** and **Fill** in landscape. Fit shows the complete frame; Fill crops
  the edges to cover the display. The choice persists when controls hide and
  returns when you rotate back to landscape during the same playback session;
- **Picture in Picture**, in landscape and on wider screens, only when a
  parent has turned it on.

When a sleep timer is running, the header shows how long is left. The header
appears and hides with the rest of the player controls. The touch lock above
the timeline hides every control except itself until it is unlocked, so a
child can watch without pausing or leaving by accident.

The bump in the timeline marks the current playback position at its peak.
Chapters appear as small gaps along the timeline and skippable intros or
credits as tinted spans. While you scrub, a preview frame and the chapter
title appear; the end time can be shown when that setting is on.

## Profiles and servers

When Plinx shows the family's profiles, continuing as the profile that was
last used needs no parent. Choosing a different profile, managing profiles,
adding a connection, or logging out asks for the parental gate. Parents manage
accounts and servers from protected settings. Downloaded media remains associated with the profile and server
that created it, so switching profiles does not expose another profile's
offline media.
