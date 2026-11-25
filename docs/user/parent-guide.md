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
Adult-only ratings, such as NC-17 or X, are never shown.

Unrated or unknown media, including clips and home videos, stays hidden unless
a parent deliberately allows it. Library visibility is a separate choice: a
visible library can still have content blocked by its rating policy.

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
  audio are allowed (both are off until a parent turns them on);
- the maximum Plinx player output level; and
- touch lock and parental PIN behavior.

The maximum playback level affects only the Plinx player. It is not hearing
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
already unlocked. Plinx never asks children to choose a profile again just
because they were away from the app for a while.

Leaving Settings, or any change that reloads the app's main screens, such as
a profile switch or Log Out, locks the parental gate again.

## Safety boundaries

No external links appear in kid-facing UI. Plinx also keeps parental settings
separate from the browsing experience and fails closed when content metadata is
missing or uncertain. Live TV and requests to a Seerr server are not offered.

For the engineering policy behind these rules, see [privacy and safety](../security/privacy-and-safety.md).
