# Youtarr integration foundation

Plinx treats Youtarr as an optional, parent-configured local service. The app
first calls `GET /external-api/v1/capabilities` with an `x-api-key` header to
establish the server's API version, role, permissions, policy, and supported
features. Explore UI and content requests deliberately sit outside this
foundation slice.

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
