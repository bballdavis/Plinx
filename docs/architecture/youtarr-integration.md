# Youtarr integration and Explore

Plinx treats Youtarr as an optional, parent-configured local service. The app
first calls `GET /external-api/v1/capabilities` with an `x-api-key` header to
establish the server's API version, role, permissions, policy, and supported
features. Explore remains off by default. Its full-screen root tab appears in
the main navigation only after a parent both saves a connection and enables
Explore.

Opening Explore performs a fresh capabilities check and requires both the
`catalog` feature and `catalog:read` scope. It loads the channel directory with
`GET /external-api/v1/channels`, then obtains the discovery feed from:

```text
GET /external-api/v1/videos
  ?status=requestable
  &sortBy=date
  &sortOrder=desc
  &pageSize=50
  [&cursor=...]
  [&search=...]
```

`requestable` is the primary availability boundary: Explore is for videos that
are not already downloaded and do not already have an active request. Plinx
omits `tabType` on this cross-channel request so Youtarr returns every media
type allowed by the key; channel-detail requests remain explicitly tab-scoped.
Plinx also rejects downloaded and requested records locally before presenting
them.
The server's opaque `nextCursor` is passed back unchanged, and appended records
are de-duplicated by video ID. Search terms are query encoded. A channel detail
uses the equivalent cursor contract at
`GET /external-api/v1/channels/:id/videos`. Partial indexes are represented by
a generic in-app notice rather than exposing server text.

The cross-channel response includes `channelDatabaseId` on each video. Plinx
uses that value when creating a request; it does not infer a channel from
display names or YouTube handles. The feed is lightly diversified on-device so
no more than two adjacent cards come from the same channel when another
eligible channel is already present. This preserves server recency as much as
possible without allowing one large channel to occupy the whole initial view.

Explore uses a mixed landscape presentation: a prominent 16:9 "New to
Explore" rail, a separate channel rail, and an adaptive 16:9 "All Videos"
grid. The channel rail remains navigation rather than the source of the
cross-channel discovery list. Card title and metadata regions have fixed
heights so rows stay aligned even when titles wrap. Each eligible card exposes
a compact, right-aligned download control instead of repeating a full-width
request bar.

Selecting a video opens a Plinx-owned detail sheet. The sheet immediately
renders the catalog record and then requests the current curated detail from:

```text
GET /external-api/v1/videos/:youtubeId
```

That response supplies the full description and optional view, like,
publication, category, language, resolution, frame-rate, quality, follower,
and tag metadata. The request action is repeated as one modal-width control
below the 16:9 artwork. Slow or unavailable detail enrichment does not hide
the already-safe catalog information, and retry remains available. The
kid-facing sheet does not render `webpageUrl` or any other external link.

The Explore presentation and navigation stack are entirely Plinx-owned.
Explore has its own persistent root navigation stack and participates in the
same main navigation as Home, Library, Search, and Downloads. It is not
presented as a sheet or compact modal. Plinx maps this owned surface onto the
upstream coordinator's otherwise-unused discovery path, avoiding a Strimr
source change while retaining independent navigation state.
Strimr's coordinator and the paired Strimr/Aether playback integration are
unchanged.

Keys with the `requests` feature and `requests:read` scope receive a My
Requests surface. Video request buttons additionally require the
`video:request` scope. Current YouTarr feature and scope grants are
authoritative; Plinx does not duplicate legacy role-name checks. Plinx sends
`POST /external-api/v1/requests/videos` with the video's YouTube ID, the
numeric Youtarr channel database ID from the video response, and a
fresh UUID idempotency key. It updates catalog state only after Youtarr returns
`created`, `duplicate`, or `already_downloaded`.

My Requests reads the paginated `GET /external-api/v1/requests` contract,
sorts requests by creation time from newest to oldest, and enriches visible
video rows through the existing curated `GET /external-api/v1/videos/:youtubeId`
detail route. Rows show same-origin authenticated artwork, video and channel
details, request time, and a right-aligned lifecycle chip. Search and Recent,
Outstanding, and All filters keep a long request history manageable. Recent
is the default and includes every active request plus terminal requests updated
within the last seven days. While the screen is visible, it polls at a
15-second interval only if a request is pending, approved, or processing.
Polling stops when all visible requests are terminal or the view disappears.
Paging is capped at 100 server pages.

`YoutarrConfigurationStore` stores only the normalized server address in
`UserDefaults`. Its API key is held by Plinx's own Keychain wrapper. An
optional authentication-proxy header is stored as one encoded name/value
credential in the Keychain. The store and credential layer are injected behind
small protocols for unit testing. Disabling the optional header deletes its
credential; removing the configuration clears all Youtarr credentials and the
stored address.

The URL policy requires HTTPS except for explicitly local addresses:
localhost, loopback, `.local`, RFC1918 IPv4, and IPv6 unique-local/link-local.
Credentials, query strings, fragments, and non-HTTP(S) schemes are rejected.
The configured base path is normalized so every API request appends
`/external-api/v1/` exactly once.

The settings entry is inside the existing parental-gated settings body. Saved
secret values are never read into view state or shown by the UI. A bullet
placeholder indicates that a secret exists, and an empty secret field retains
the matching credential when testing or saving other connection changes.

The current catalog contract returns same-origin external-API thumbnail assets.
Plinx does not construct or request Google/YouTube thumbnail URLs. Only an
exact scheme/host/effective-port match under the configured
`/external-api/v1/` path receives `x-api-key` and the optional
proxy-authentication header. Redirects are rejected and Plinx uses a bounded,
memory-only image cache. A durable upstream thumbnail cache belongs in Youtarr,
so every Plinx client benefits without increasing Google API or image-host
traffic.

The secret-free CI gate mounts Youtarr's real external router over its canonical
sanitized dataset and drives Plinx through production HTTP and UI code. The
separate credentialed smoke validates a deployed parent-configured service.
Both are documented in
[Youtarr live smoke tests](../development/youtarr-live-smoke-tests.md).

The sanitized v1 consumer contract is owned by Youtarr and vendored byte-for-byte
under the Plinx unit-test fixtures. `config/youtarr-contract.env` pins the
producing commit and checksum. Run
`scripts/verify_youtarr_contract_fixture.sh --check` to verify it or `--update`
after intentionally advancing the pin and sibling checkout.
