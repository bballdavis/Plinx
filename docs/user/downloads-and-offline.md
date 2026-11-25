---
sidebar_position: 5
---

# Downloads and offline playback

Plinx can download authorized movies and episodes for offline playback. Choose
a download quality in protected settings to balance storage use and video
quality. Downloads are available on iPhone and iPad only; Apple TV does not
offer download controls or offline playback.

From a show's details, Download opens a season-and-episode picker. From a
season's details, the same picker stays scoped to that season. Select All queues
every episode that is not already downloaded, or individual episodes can be
chosen before confirming.

## Download quality

The Original option downloads the selected source media part directly. The
remaining presets cap the video bitrate and
resolution, from 20 Mbps at 1080p down to 0.7 Mbps at 328p. The selected preset
applies to downloads started after the setting changes; it does not rewrite
files already stored on the device.

Reduced-quality presets are used only when they are estimated to save at least
20 percent. The estimate combines the selected video bitrate, 192 kbps stereo
AAC audio, and container overhead. If the estimate cannot meet that threshold,
that item downloads at Original quality instead.

For a reduced-quality Plex download, Plinx submits the item to Plex Media
Server's download queue. The Downloads tab shows a preparation phase while the
server prepares the item; a transcode of unknown length shows the bytes
received so far. The device transfer begins only when the queued media is
available. Server-side preparation can continue while Plinx is not active, and
Plinx resumes monitoring it when the correct server and profile return. The
parent-gated Manage Downloads screen shows storage use and each download's
quality.

This flow requires Plex Media Server 1.41.9 or newer and a Plex account that is
permitted to use server downloads/transcoding. A failed item stays on the
Downloads tab marked **Download failed**. Tap it to choose **Redownload** or
**Remove**. A redownload resumes or prepares the file again, rechecks the
current content rules, and needs a connection to the same server and profile.
If it cannot start, the failed item stays so you can try again later. Failed
items also appear in the parent-gated Manage Downloads screen.

## Download rules

- A download must be allowed by the current content policy, and so must each
  episode of a season or show.
- Each download belongs to the server and profile (Plex Home user or Jellyfin
  user) that created it, and only that profile sees it.
- The first time this version runs, Plinx moves the profile records that
  earlier versions kept for each download onto the downloads themselves.
- A download with no profile record, such as one made before Plinx tracked
  profiles, belongs to no profile. Children never see it. A parent sees it
  under **Other downloads** in Manage Downloads and can delete it there, but it
  cannot be played.
- Plinx validates download integrity before it becomes available to play.
- HTML, JSON, XML, empty, truncated, and unsuccessful HTTP responses are never
  promoted to playable media.
- A title that later becomes blocked by a parent setting remains unavailable,
  even if it was downloaded earlier.

Use the Downloads tab to monitor, play, or remove offline media. If an item is
not available, reconnect to the intended server/profile and confirm the parent
rating and library settings still allow it.

During an internet or server outage, the profile's downloads stay available.
**Log Out** hides every download until the profile that made it signs in
again, but does not delete the media files.

When Plinx opens, it shows its loading screen while it connects. The
**Connection unavailable** card and the offline Downloads view appear only if
that connection fails or the device reports no network. When the network comes
back, Plinx retries on its own; **Try Again** shows progress while a retry runs.
