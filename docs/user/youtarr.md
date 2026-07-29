---
sidebar_position: 6
---

# Optional Youtarr integration

Youtarr is an optional, parent-configured local service. It is disabled by
default and only appears after a parent saves a connection and explicitly
enables Explore.

Plinx checks Youtarr capabilities before showing catalog or request features.
Returned videos are filtered again on-device by both the Youtarr permissions
and the current Plinx rating policy. Unknown media types and unknown ratings
stay hidden unless both policies clearly permit them.

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
