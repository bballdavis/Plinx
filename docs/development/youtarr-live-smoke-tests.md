# Youtarr live smoke tests

Plinx has two Youtarr integration gates. The required synthetic gate runs in CI
without credentials or a full Youtarr process:

```bash
scripts/tests/youtarr_synthetic_ui_tests.sh
```

It starts Youtarr's real external API router on loopback over the canonical
sanitized contract dataset. Plinx then uses its production `URLSession` client
and production Explore, detail, artwork, request, and My Requests views. The
gate covers successful rendering and request writes plus empty, locally
filtered, unauthorized, malformed, delayed/cancelled, and server-error states.
The server uses the fixed local port `39087`; an existing listener is a failure.
The fixture's ordinary catalog is calibrated to sanitized live structural
characteristics—field types and nullability, four-channel scale, a video-heavy
video/short/livestream mix, common kid ratings, pagination, and same-origin
artwork paths—without copying real media data. Both repositories assert that
profile locally, so normal development does not require the deployed server.

The second gate is an opt-in live test for a parent-configured Youtarr. It is a
pre-release check rather than an ordinary CI dependency.

Set `PLINX_YOUTARR_URL` to the deployed test service. Alternatively, explicitly
select a simulator with saved Youtarr configuration through
`PLINX_YOUTARR_SIMULATOR_ID`; the runner reads only its saved base URL. The
service's channels must have ratings that overlap the tested Plinx profile;
the default smoke profile allows `TV-Y`.

Run the read-only API contract, authenticated landscape-thumbnail, Explore UI,
and Requests UI checks with:

```bash
scripts/tests/youtarr_live_smoke_tests.sh
```

Before building, the runner checks capabilities plus the paginated approved
channel and requestable-video totals. It reports authentication, transport,
HTTP, zero-approved-channel, and zero-requestable-video failures separately;
it never print response bodies or credentials.

The runner uses `PLINX_YOUTARR_API_KEY` when set. Otherwise it reads the
dedicated local test key from macOS Keychain service
`com.bballdavis.plinx.integration-test`, account `plinx.youtarr.apiKey`. It
injects the secret only into the selected simulator process environment and
removes it when the run finishes.

The isolated live UI route keeps the default runner independent from Plex. To
also exercise the real bottom-tab navigation on a simulator that already has a
valid Plex session, run the runner with both opt-ins:

```bash
PLINX_YOUTARR_LIVE_MAIN_TAB=1 \
PLINX_YOUTARR_SIMULATOR_ID="<configured simulator UUID>" \
scripts/tests/youtarr_live_smoke_tests.sh
```

That second opt-in supplies an in-memory test-only Youtarr override to
`RootTabView`, selects `main.tab.explore`, and verifies that activating the
full Explore tab refreshes and renders a requestable video. It never writes
the simulator's saved configuration or Keychain and never affects normal
launches or physical-device storage.

To exercise an actual video request against a disposable Youtarr fixture:

```bash
scripts/tests/youtarr_live_smoke_tests.sh --write
```

The write check can create a request and consume server-side quota, so it is
intentionally separate from the default read-only run.
