# Youtarr integration and Explore

Plinx treats Youtarr as an optional, parent-configured local service. The app
first calls `GET /external-api/v1/capabilities` with an `x-api-key` header to
establish the server's API version, role, permissions, policy, and supported
features. Explore remains off by default. Its Home entry appears only after a
parent both saves a connection and enables Explore.

Opening Explore performs a fresh capabilities check and requires both the
`catalog` feature and `catalog:read` scope. It then uses deterministic
`page`/`pageSize` requests for `GET /external-api/v1/channels` and
`GET /external-api/v1/channels/:id/videos`. Search terms are query encoded and
pagination appends de-duplicated records in page order. Partial channel indexes
are represented by a generic in-app notice rather than exposing server text.

The Explore presentation and navigation stack are entirely Plinx-owned.
Strimr's coordinator and the paired Strimr/MPVKit repositories are unchanged.
This browse slice displays download/request status but does not submit requests.

`YoutarrConfigurationStore` stores only the normalized server address in
`UserDefaults`. Its API key is held by Plinx's own Keychain wrapper. Both are
injected behind small protocols for unit testing. Removing configuration clears
both stores.

The URL policy requires HTTPS except for explicitly local addresses:
localhost, loopback, `.local`, RFC1918 IPv4, and IPv6 unique-local/link-local.
Credentials, query strings, fragments, and non-HTTP(S) schemes are rejected.
The configured base path is normalized so every API request appends
`/external-api/v1/` exactly once.

The settings entry is inside the existing parental-gated settings body. A saved
key is never read into or shown by the UI; leaving the key field empty keeps an
existing key when replacing the server address.

Youtarr may return allowlisted YouTube/Google HTTPS thumbnails or same-origin
external-API assets. Public images use the system image loader without
credentials. Only an exact scheme/host/effective-port match under the configured
`/external-api/v1/` path receives `x-api-key`, using a redirect-rejecting
ephemeral session and a bounded memory-only cache.
