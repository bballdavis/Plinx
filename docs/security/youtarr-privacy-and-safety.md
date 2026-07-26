# Youtarr privacy and safety controls

Youtarr connection configuration is a parent-only action behind Plinx's
existing parental gate. The configuration screen has no external links and
does not expose an Explore experience to a child-facing surface.

The API key is stored only in the system Keychain and is sent only as the
`x-api-key` request header to the configured Youtarr server. Plinx does not log
the API key or HTTP response bodies. Connection errors are mapped to generic,
user-facing states instead of exposing server responses.

App Transport Security permits local-network access only, so a parent can
connect to a self-hosted HTTP Youtarr instance. Plinx does not enable arbitrary
HTTP loads or certificate bypasses. Public HTTP addresses are rejected; HTTP
is restricted to the local-network address classes documented in
`docs/architecture/youtarr-integration.md`. iOS presents the parent-facing
local-network purpose string before granting access.

No telemetry or new third-party dependencies are added.
