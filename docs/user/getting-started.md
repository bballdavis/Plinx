---
sidebar_position: 2
---

# Getting started

Plinx is designed for a parent or guardian to set up first, then hand over for
family browsing.

## Before you begin

You need one of:

- a Plex account with access to a Plex Media Server and the libraries you want
  to make available, plus a Plex Home profile if your family uses them; or
- a Jellyfin server and a user account on it.

## First-time setup

The first screen asks a grown-up to choose how to connect: **Continue with
Plex** or **Use a Jellyfin server** (on Apple TV, **Plex** or **Jellyfin**).
On iPhone and iPad, **Sign-in information** on that screen explains setup and
offers a sample library you can explore first.

1. Sign in with the Plex account used to manage your server, or sign in to
   your Jellyfin server (see [Sign in to Jellyfin](#sign-in-to-jellyfin)).
2. Choose a profile. Protected Plex Home profiles require their Plex PIN.
3. Choose the servers that profile should use.
4. Open Settings through the parental gate and set the libraries, rating limits,
   and other controls appropriate for your family.
5. Return to the main tabs to browse, search, and watch approved media.

The first setup screen is intentionally a grown-up step. Once configured,
children see the Plinx browsing experience rather than account-management
choices.

## Sign in to Jellyfin

1. Choose **Use a Jellyfin server** (on Apple TV, **Jellyfin**).
2. Enter your server's address, for example `http://192.168.1.20:8096`. On
   Apple TV you can instead choose **Search local servers** to find Jellyfin
   servers on your network and pick one. iPhone and iPad do not offer the
   search yet, so enter the address there.
3. Sign in with your Jellyfin username and password. If the server has Quick
   Connect turned on, you can instead choose **Use Quick Connect** and enter
   the code Plinx shows in a Jellyfin app where you are already signed in.

Plinx sends the password only to your server and does not keep it. It stores
the access token the server returns in the device Keychain. If no Plinx
profile exists yet, Plinx creates one named after the Jellyfin user; a parent
can add more Jellyfin servers or a Plex account later under **Accounts and
servers** in protected settings.

Plinx applies its own rating limits and library visibility to every Jellyfin
title, in addition to any parental controls set on the Jellyfin user. If you
give a title a custom rating in Jellyfin's metadata editor, Plinx uses
whichever of that and the title's parental rating is stricter. A custom
rating can hide a title from your child, but it cannot unhide a title whose
parental rating is above your limit.

## Try Plinx without an account

On iPhone or iPad, tap **Sign-in information**, then **Explore the Demo Library**.
On Apple TV, choose Plex, then select **Explore the Demo Library** on the
sign-in screen. The sample library is offered only while no account is set
up.
The sample library includes movies, episodes, collections, playlists, and a
sample Explore catalog. Its original 90-second videos support playback,
seeking, audio tracks, captions, and downloads without an external server.
Sample requests stay in the demo and do not request external videos.

The demo parental PIN is **2468**. Demo controls are separate from your family's
settings and reset when you enter the demo again. Sample downloads remain
until deleted; re-enter the demo after relaunch to access them. Log out through
Settings to leave the sample library and return to account setup.

See the [product tour](product-tour.md) for screenshots.

## Choose a device

Plinx 2026.08 supports iPhone, iPad, and Apple TV. Use iPhone or iPad to
download approved media for offline playback. On Apple TV, use the Siri Remote
to browse and stream; download actions are intentionally unavailable. See the
[Apple TV guide](apple-tv.md) for remote navigation and troubleshooting.

## If a server is missing

Confirm that the account can see the server in Plex (or that the Jellyfin
server address and user are correct), that the server is online, and that the
selected profile has access to the intended libraries. A parent can add,
reconnect, or choose servers later under **Accounts and servers** in protected
settings.
