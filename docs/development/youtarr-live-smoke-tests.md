# Youtarr live smoke tests

Plinx includes opt-in live tests for the parent-configured Youtarr integration.
They skip unless the live-test environment is present, so ordinary unit and UI
test runs do not require a real server.

The default local fixture is expected at `http://127.0.0.1:3087`. Its channels
must have ratings that overlap the tested Plinx profile; the default smoke
profile allows `TV-Y`. This deliberately catches the case where Youtarr has a
populated catalog but Plinx correctly filters every row.

Run the read-only API contract, authenticated landscape-thumbnail, Explore UI,
and Requests UI checks with:

```bash
scripts/tests/youtarr_live_smoke_tests.sh
```

The runner uses `PLINX_YOUTARR_API_KEY` when set. Otherwise it reads the
dedicated local test key from macOS Keychain service
`com.bballdavis.plinx.integration-test`, account `plinx.youtarr.apiKey`. It
injects the secret only into the selected simulator process environment and
removes it when the run finishes.

The isolated live UI route keeps the default runner independent from Plex. To
also exercise saved configuration and the real bottom-tab navigation on a
simulator that already has a valid Plex session and Youtarr configuration, run
the runner with both opt-ins:

```bash
PLINX_YOUTARR_LIVE_MAIN_TAB=1 \
PLINX_YOUTARR_SIMULATOR_ID="<configured simulator UUID>" \
scripts/tests/youtarr_live_smoke_tests.sh
```

That second opt-in selects `main.tab.explore` and verifies that activating the
full Explore tab refreshes and renders a requestable video. It replaces the
selected simulator's saved Youtarr URL and API key with the dedicated
live-test configuration; it never affects normal launches or physical-device
storage.

To exercise an actual video request against a disposable Youtarr fixture:

```bash
scripts/tests/youtarr_live_smoke_tests.sh --write
```

The write check can create a request and consume server-side quota, so it is
intentionally separate from the default read-only run.
