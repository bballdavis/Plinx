---
sidebar_position: 3
---

# Parent guide

Plinx keeps parent-only settings behind a math challenge or PIN. The gate is
also used for account, server, profile, and optional service configuration.

## Content controls

Parents can set separate movie and television rating ceilings. The default
limits are G and TV-Y, and parents can raise either limit to any supported
rating. Plinx filters browsing, search, playlists, and
playback; it checks content again immediately before playback starts.
Adult-only ratings, such as NC-17, X, or another country's 18, 19, or 21
certificate, are never shown.

Unrated or unknown media, including clips and home videos, stays hidden unless
a parent deliberately allows it. Library visibility is a separate choice: a
visible library can still have content blocked by its rating policy.

Seasons and episodes follow their show's rating. An episode of a show above
your TV limit stays hidden even when the episode itself has no rating, so
allowing unrated content (which many Jellyfin servers need before any TV shows
up) never opens episodes of a blocked show. An episode without a rating of its
own is judged by its show's rating.

Collections and playlists appear as plain tiles, without the poster collage
the server makes from their contents, because that collage can show titles
above your limits. Opening one lists only the titles your limits allow.

## Family settings

Protected settings can control:

- visible libraries for each profile, and the home-screen arrangement;
- accounts and servers: Plex accounts and Jellyfin servers, and which
  servers each profile uses;
- switching to another profile;
- appearance, button sizing, and motion preferences;
- download quality and offline access;
- player options such as autoplay, the sleep timer, skipping intros and
  credits, audio, subtitles, and whether Picture in Picture and background
  audio are allowed on iPhone and iPad (both are off until a parent turns
  them on; while both are off, leaving Plinx closes the player);
- the maximum Plinx player output level; and
- touch lock and parental PIN behavior.

The Plinx player plays at the maximum playback level you set (70% until you
change it). The level affects only the Plinx player. It is not hearing
protection and cannot limit device, headphone, AirPlay, receiver, or television
volume.

## Accounts and servers

Plinx can use Plex Media Servers through a Plex account and Jellyfin servers
at the same time. Add, reconnect, or remove a connection under **Accounts and
servers**. On iPhone and iPad, removing an account asks whether to keep or
delete the downloads made with it.

**Log Out** removes every account and server from the device. Before it
does, Plinx sends any watch progress recorded offline to the servers. Downloads
stay on the device but are hidden until the profile that made them signs in
again, and the parental gate locks.

## Profiles

When Plinx asks who is watching, continuing as the profile that was last used
needs no parent. Switching to a different profile, managing profiles, adding a
connection, and logging out all ask for the parental gate, unless Settings is
already unlocked. If Plinx does not remember who watched last, for example
after a Plex Home user or a profile was removed, choosing any profile asks for
the parental gate. Plinx never asks children to choose a profile again just
because they were away from the app for a while.

**Manage profiles** appears on the profile picker even when the current Plex
profile is a restricted one, because the parental gate, not the Plex profile,
decides who may manage profiles. **Log Out** on the profile picker is the same
full Log Out as in Settings.

Leaving Settings, or any change that reloads the app's main screens, such as
a profile switch or Log Out, locks the parental gate again. Leaving the app
locks it too: Settings and profile management opened from the profile picker
show the parental gate again when you come back.

Signing in to Plex from Settings on iPhone or iPad is the one exception,
because the sign-in itself takes you out of Plinx. While a Plex sign-in is
in progress, you can switch to a password manager, an authenticator, or your
email and come back to finish. If you are away for more than five minutes,
Plinx shows the parental gate when you come back and you start the sign-in
over. If the sign-in finishes or is cancelled while you are away, the gate
locks then.

## Safety boundaries

No external links appear in kid-facing UI. Plinx also keeps parental settings
separate from the browsing experience and fails closed when content metadata is
missing or uncertain. Live TV and requests to a Seerr server are not offered.

Some actions change the family's server or account, so Plinx shows them only
while the parental gate is unlocked: adding to a playlist and renaming or
deleting one, the Plex watchlist, and subtitle search (including automatic
subtitle search). Kids also don't see Shuffle on a media details page.
Starting SharePlay from Plinx is not offered.

For the engineering policy behind these rules, see [privacy and safety](../security/privacy-and-safety.md).
