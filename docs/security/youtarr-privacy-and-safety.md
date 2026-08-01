# Youtarr privacy and safety controls

Youtarr connection configuration is a parent-only action behind Plinx's
existing parental gate. The configuration screen has no external links.
Explore is disabled by default, and removing the connection also disables it.
The kid-facing entry is hidden unless both a connection and the parent setting
are present.

The API key is stored only in the system Keychain and is sent as the
`x-api-key` request header to the configured Youtarr server. A parent may
configure one additional header for an authentication proxy; its name and
value are stored together in the Keychain. Plinx rejects malformed names,
line breaks in values, and headers managed by Plinx or URL loading. Disabling
the additional header and saving deletes the pair. Plinx does not log either
credential or HTTP response bodies. Connection errors are mapped to safe
user-facing categories instead of exposing server responses. Rejected
credentials tell the parent to replace or reconfigure the key; transport,
unsupported-version, malformed-response, and server-unavailable states remain
distinct.

Explore checks capabilities before loading the catalog. Video records are
filtered again on-device against the Youtarr key policy and Plinx's current
rating policy. Media types are limited to `video`, `short`, and `livestream`
and must also be allowed by the key. Unknown rating values and unknown media
types are hidden. Unrated videos appear only when both policies permit them.
This defense-in-depth filter applies even though Youtarr filters its response.

Thumbnail URLs are never displayed as links. Current Youtarr catalog responses
provide same-origin proxy URLs, and Plinx does not derive or contact public
YouTube/Google image hosts. The API key and optional additional header are
attached only to same-origin URLs under the configured external API prefix.
Redirects are rejected and authenticated images use a bounded, memory-only
cache.

App Transport Security permits local-network access only, so a parent can
connect to a self-hosted HTTP Youtarr instance. Plinx does not enable arbitrary
HTTP loads or certificate bypasses. Public HTTP addresses are rejected; HTTP
is restricted to the local-network address classes documented in
`docs/architecture/youtarr-integration.md`. iOS presents the parent-facing
local-network purpose string before granting access.

No telemetry or new third-party dependencies are added.

Video requests use a new random idempotency UUID for each deliberate tap.
Duplicate taps are disabled while a request is in flight, and only a confirmed
server response changes a video's requested/downloaded state. Request response
bodies and server-provided messages are not shown or logged. My Requests
performs no background refresh: polling is cancelled on navigation and runs
only while the page is visible and an active request needs a status update.
