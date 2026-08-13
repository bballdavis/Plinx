---
sidebar_position: 4
---

# Using Plinx

For a quick cross-device feature overview, see the [product tour](product-tour.md).

## Home and libraries

The home screen loads recently added media from the same Plex library catalogs
used by Library Browse. Parents can select which libraries appear and how home
sections are arranged. Movie and TV libraries can be combined or split, while
YouTube and other none-agent video libraries remain separate landscape rows.
If one library is temporarily unavailable, other Home rows can still load.
If a pull-to-refresh cannot reach the server, Home keeps the rows that were
already on screen instead of replacing them with a disconnected state.

Open Libraries to browse an individual Plex library, its recommendations,
collections, and full grids. The available sections reflect the current parent
controls.

Collections are hidden by default for new installations. Parents can enable
them in Settings; an existing saved preference is preserved.

## Search

Search looks across the selected Plex server. Results are filtered by the same
rating and visibility rules used throughout Plinx, so a blocked item does not
become discoverable just because it matches a search term.

## Playback

Choose an item to view its details, resume progress, select an episode, or
start playback. Plinx supports the playback capabilities provided by the paired
Plex and Strimr foundations, including available audio tracks and playback
resume.

Before a play queue is shown, Plinx fetches current metadata and re-applies
the active content policy. This protects direct actions, playlist playback,
and supported SharePlay-initiated playback paths.

The player overlay keeps high-contrast rewind, play or pause, and fast-forward
controls centered over video; they scale up responsively on larger layouts.
Its existing back and settings controls and the video title are 50% larger for
easier reading and targeting without adding a
second persistent back button or rating chip over the video.

## Profiles and servers

Parents can switch Plex Home profiles or Plex servers from protected settings.
Downloaded media remains associated with the profile and server that created
it, so switching identity does not expose another profile's offline media.
