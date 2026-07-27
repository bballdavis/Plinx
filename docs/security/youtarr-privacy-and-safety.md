# Youtarr privacy and safety controls

Youtarr connection configuration is a parent-only action behind Plinx's
existing parental gate. The configuration screen has no external links.
Explore is disabled by default, and removing the connection also disables it.
The kid-facing entry is hidden unless both a connection and the parent setting
are present.

The API key is stored only in the system Keychain and is sent only as the
`x-api-key` request header to the configured Youtarr server. Plinx does not log
the API key or HTTP response bodies. Connection errors are mapped to generic,
user-facing states instead of exposing server responses.

Explore checks capabilities before loading the catalog. Video records are
filtered again on-device against the Youtarr key policy and Plinx's current
rating policy. Media types are limited to `video`, `short`, and `livestream`
and must also be allowed by the key. Unknown rating values and unknown media
types are hidden. Unrated videos appear only when both policies permit them.
This defense-in-depth filter applies even though Youtarr filters its response.

Thumbnail URLs are never displayed as links. An API key is attached only to
same-origin URLs under the configured external API prefix. Redirects are
rejected for authenticated image requests, while public HTTPS images are
loaded without any Youtarr header and only from an explicit YouTube/Google
image-host allowlist. Authenticated images use a bounded, memory-only cache.

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
