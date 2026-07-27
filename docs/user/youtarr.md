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
system Keychain. Plinx only sends that key to the configured Youtarr service;
it does not log the key or response bodies.

For the technical transport and privacy rules, see [Youtarr privacy and safety](../security/youtarr-privacy-and-safety.md).
