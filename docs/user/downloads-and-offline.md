---
sidebar_position: 5
---

# Downloads and offline playback

Plinx can download authorized movies and episodes for offline playback. Choose
a download quality in protected settings to balance storage use and video
quality.

From a show's details, Download opens a season-and-episode picker. From a
season's details, the same picker stays scoped to that season. Select All queues
every episode that is not already downloaded, or individual episodes can be
chosen before confirming.

## Download quality

The Original option asks Plex to preserve the source quality whenever the
server can deliver it directly. The remaining presets cap the video bitrate and
resolution, from 20 Mbps at 1080p down to 0.7 Mbps at 328p. The selected preset
applies to downloads started after the setting changes; it does not rewrite
files already stored on the device.

For a reduced-quality download, Plinx submits the item to Plex Media Server's
download queue. The Downloads tab shows a preparation phase while the server
decides whether it can direct play, direct stream, or must transcode the item.
The device transfer begins when the queued media is available. Server-side
preparation can continue while Plinx is not active, and Plinx resumes monitoring
it when the correct server and profile return.

This flow requires Plex Media Server 1.41.9 or newer and a Plex account that is
permitted to use server downloads/transcoding. A failed item remains visible in
the parent-gated Manage Downloads screen so it can be removed and retried.

## Download rules

- A download must be allowed by the current content policy.
- Offline media downloaded by the current version is tied to the Plex server
  and profile that created it.
- Downloads already on a device when Plinx is upgraded have no historical
  profile record. Plinx treats those legacy downloads as shared offline media,
  but still hides and blocks playback whenever they exceed the active profile's
  current rating limits.
- Plinx validates download integrity before it becomes available to play.
- HTML, JSON, XML, empty, truncated, and unsuccessful HTTP responses are never
  promoted to playable media.
- A title that later becomes blocked by a parent setting remains unavailable,
  even if it was downloaded earlier.

Use the Downloads tab to monitor, play, or remove offline media. If an item is
not available, reconnect to the intended server/profile and confirm the parent
rating and library settings still allow it.
