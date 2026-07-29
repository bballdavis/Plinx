---
sidebar_position: 6
---

# Optional Youtarr integration

Youtarr is an optional, parent-configured local service. It is disabled by
default and its full-screen Explore tab only appears in the main navigation
after a parent saves a connection and explicitly enables Explore.

Plinx checks Youtarr capabilities before showing catalog or request features.
Returned videos are filtered again on-device by both the Youtarr permissions
and the current Plinx rating policy. Unknown media types and unknown ratings
stay hidden unless both policies clearly permit them.

When Youtarr has requestable videos but every result is above the current
profile's rating limit, Explore says that nothing matches the profile instead
of describing the server catalog as empty. A parent can then review the
channel ratings in Youtarr or the profile rating ceiling in Plinx.

Explore combines eligible videos from all indexed channels into one discovery
feed. It shows newest videos in a landscape rail, provides a separate channel
browser, and continues with a landscape video grid. The feed is specifically
limited to videos that are not already downloaded and do not already have an
active request. Sending a request removes that video from Explore after
Youtarr confirms the result.

Each video card has a small download control beside its channel and rating.
Selecting the rest of the card opens Video Details with larger landscape
artwork, a full-width request control, duration and rating, and the additional
description and technical information available from Youtarr. This detail
view stays inside Plinx and does not provide links to YouTube or other external
sites.

Video artwork is loaded through the configured Youtarr service. Plinx does not
contact a public thumbnail host directly or expose thumbnail links in the
kid-facing interface.

The connection address is stored on-device and the API key is held in the
system Keychain. If an authentication proxy protects Youtarr, a parent can
also configure one additional authentication header; its name and value are
stored together in the Keychain. Plinx sends these credentials only to the
configured Youtarr service and does not log them or response bodies. Turning
off the additional header and saving the connection deletes that header.

Saved secret fields display a password-style mask to show that a value exists.
The mask is only an indicator: Plinx does not place the saved secret into the
settings form.

For the technical transport and privacy rules, see [Youtarr privacy and safety](../security/youtarr-privacy-and-safety.md).
