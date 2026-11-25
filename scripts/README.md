# Plinx Build & Run Scripts

All executable scripts use Bash. They can be invoked directly from any shell,
for example `./scripts/run_ipad_sim.sh`; if launched with `zsh script.sh`, they
re-enter through Bash before resolving repository-relative paths.

Convenient shell scripts for building and running the Plinx iOS app on the simulator, plus UI/logic tests.

## Directory Layout

The root contains the supported developer and release entry points. Specialized
implementation helpers live in focused subdirectories:

- `support/` — sourced build/test helpers and the Xcode project resource patcher
- `release/` — screenshot fixtures, release preflight/image helpers, and export options
- `tests/` — test harnesses and their fixtures
- `branding/` — deterministic brand asset generation

Scripts in `support/` and `release/` are implementation details; invoke the
documented root-level commands when one exists.

## Source Of Truth

Everything the app compiles is in this repository. The media, provider,
session, and player code Plinx absorbed from Strimr lives in `PlinxApp/Core`
and `PlinxApp/Platform`; there is no sibling checkout to fetch, pin, or verify.
Swift packages (AetherEngine, GRDB, SwiftAssRenderer) are pinned exactly in
`PlinxApp/project.yml` and resolved by Swift Package Manager.

Build and test scripts build from your working tree, so uncommitted edits are
part of the build. Release packaging (`build_compliance_bundle.sh`) requires a
clean, committed checkout.

Upstream Strimr is reviewed and ported by hand, not pulled. See
[upstream Strimr provenance](../docs/maintenance/upstream-strimr.md).

## Scripts

### `branding/generate-assets.mjs` — Generate Brand And Platform Assets

Traces the approved Plink Loop and wordmark sources, then exports the native
asset-catalog images, iOS appearance variants, tvOS layered icons and Top Shelf
artwork, launch background, website graphics, and marketing files.

```bash
# Regenerate committed outputs.
npm run branding:generate --prefix website

# Verify committed outputs without modifying them.
npm run branding:check --prefix website
```

The palette and export contract live in
`assets/branding/brand-manifest.json`. Do not edit a generated logo or icon
directly; update the approved source or manifest and regenerate.

### `generate_xcodeproj.sh` — Generate the App Project

Runs XcodeGen. The project's post-generation step
(`support/patch_resources.py`) adds the asset catalog, localizations, demo
media, and privacy manifest to each app target's own resource phase (the one
XcodeGen generates for the license texts, or a new target-owned phase when
there is none). The iOS phase also compiles the launch storyboard. Keep exactly
one resource phase per app target, and never share a phase between iOS and
tvOS; Xcode may then omit resources from one platform bundle.

The generated `PlinxApp/Plinx.xcodeproj` is committed as Xcode Cloud's stable
project input while `PlinxApp/project.yml` remains canonical. After changing
the project specification, regenerate and commit both. In a clean checkout,
`./scripts/generate_xcodeproj.sh --check` verifies that generation produces no
project diff after Xcode applies its current shared-scheme normalization.
`./scripts/generate_xcodeproj.sh --check-portable` performs the generation and
diff without invoking Xcode, so the automatic project-freshness workflow can
run on an Ubuntu runner.

---

### `ui_tests.sh` — Run UI & Logic Tests

Runs Swift Testing tests for both PlinxCore and PlinxUI, with optional snapshot tests.

```bash
# Run all logic tests (PlinxCore + PlinxUI)
./scripts/ui_tests.sh

# Run PlinxCore tests only
./scripts/ui_tests.sh --core

# Run PlinxUI tests only
./scripts/ui_tests.sh --ui

# Run snapshot diffs on iPhone 15 simulator
./scripts/ui_tests.sh --snapshots

# Record baseline snapshots (first run, then commit __Snapshots__/)
./scripts/ui_tests.sh --record
```

**What it does:**
- **Logic tests** (PlinxCore + PlinxUI): Swift Testing tests — fast, no simulator needed
  - `PlinxRating` parsing, ordering, classification
  - `SafetyInterceptor` label & rating filtering
  - `PlinxTheme`, `PlinxMediaCard`, `PlinxErrorView` property tests
- **Snapshot tests** (PlinxUI only): Pixel-diff screenshots at three device widths
  - iPhone SE (compact), iPhone 15 (standard), iPad Pro 13" (regular)
  - Catches layout breakage, missing nav bars, UI regressions

**Output:** Colored summary of pass/fail for each test layer.

See [docs/development/ui-testing.md](../docs/development/ui-testing.md) for full documentation.

---

### `live_library_parity_tests.sh` — Run Live Browse/Recommend Parity Tests

Loads `test_creds.yaml`, injects Plex credentials into the test process, and runs:
`Plinx-iOS-UnitTests/LibraryFilteringParityLiveTests` by default.

```bash
# Run iOS parity against the default simulator destination
./scripts/live_library_parity_tests.sh

# Run iOS parity against a custom destination string
./scripts/live_library_parity_tests.sh 'platform=iOS Simulator,name=iPhone 17'

# Run Apple TV parity against a discovered Apple TV simulator
./scripts/live_library_parity_tests.sh --appletv

# Run Apple TV parity against a custom destination string
./scripts/live_library_parity_tests.sh --appletv 'platform=tvOS Simulator,name=Apple TV'
```

**What it does:**
- Reads `PLINX_PLEX_SERVER_URL` and `PLINX_PLEX_TOKEN` from repository-root `test_creds.yaml`
- Exports both direct and `SIMCTL_CHILD_*` env vars for simulator test propagation
- Runs targeted live parity tests and writes full logs to `/tmp/plinx_live_library_parity_ios.log` or `/tmp/plinx_live_library_parity_tvos.log`
- Writes result bundles to `/tmp/Plinx_live_library_parity_ios.xcresult` or `/tmp/Plinx_live_library_parity_tvos.xcresult`
- In Apple TV mode, exercises the tvOS paged `itemsByIndex` browse/collections models and verifies compact indexing, collection exclusion for movie/show browse, and Other Videos unrated handling

**Output:** Clear pass/fail status plus extracted error lines on failure.

---

### `run_iphone_sim.sh` — Build, Install & Run

Generates the Xcode project, builds the app, and launches it on a simulator.
The script now supports a special `generic` argument which avoids
looking up a particular device UDID; this is useful in CI or when you
just want to build for "any iPhone simulator".

```bash
# Run on iPhone 16 Pro Max (default)
./scripts/run_iphone_sim.sh

# Run on a specific device
./scripts/run_iphone_sim.sh "iPhone 15"

# Build/install on whatever simulator is available (no UDID lookup)
./scripts/run_iphone_sim.sh generic
```

The bundle identifier is automatically read from the built app, so you
no longer need to keep the hard‑coded placeholder in the script. It
also avoids the missing‑bundle‑ID error that could occur when the
`Index.noindex` build tree was accidentally used.

**What it does:**
1. Finds and boots the specified simulator
2. Generates `Plinx.xcodeproj` from `project.yml` (XcodeGen)
3. Builds the Plinx-iOS target in Debug configuration
4. Installs the app on the simulator
5. Launches the app

**Output:** The app should open automatically on the simulator.

---

### `build_only.sh` — Build Only

Generates the project and builds the app without installing or running.
The script automatically falls back to a generic simulator destination
when the named device cannot be found (or when CoreSimulator isn't
reachable), and it will now avoid reporting the bogus app from
`Index.noindex`.

```bash
# Build for iPhone 16 Pro Max (default)
./scripts/build_only.sh

# Build for a specific device
./scripts/build_only.sh "iPhone 15"

# If the chosen device isn't available, it will build with
# `generic/platform=iOS Simulator` instead and still report a path.
```

**What it does:**
1. Finds the specified simulator (doesn't need to be booted)
2. Generates `Plinx.xcodeproj`
3. Builds the app in Debug configuration
4. Reports build location

**Output:** Shows the path to the built `.app` bundle. Use `run_iphone_sim.sh` to install & run.

---

### `clean.sh` — Clean Build Artifacts

Removes generated outputs and the shared Plinx compiler caches. Normal builds
reuse these caches; run this only when you need a genuinely clean build.

```bash
./scripts/clean.sh
```

**What it removes:**
- `Plinx.xcodeproj` (regenerated from project.yml on next build)
- repository-local build, SwiftPM, and website outputs
- the shared Xcode DerivedData root
- the shared SwiftPM scratch root

By default, reusable caches live under:

- `~/Library/Caches/Plinx/DerivedData`
- `~/Library/Caches/Plinx/SwiftPM`

Override them when an isolated cache is required:

```bash
PLINX_CACHE_ROOT=/path/to/cache ./scripts/run_iphone_sim.sh
```

**Use when:** You encounter weird build cache issues or want a fresh build.

The build and test scripts intentionally use one Xcode DerivedData path and
one stable SwiftPM scratch path per package. They do not delete those paths at
the start of each run, so dependency checkouts and compiled modules can be
reused across iPhone, iPad, tvOS, package, and snapshot tests.

---

### `build_release_archive.sh` — Build Release Archive For TestFlight

Builds a signed archive for App Store Connect and validates the packaged app bundle before upload.

```bash
# Build with an auto-generated unique build number
./scripts/build_release_archive.sh

# Build with an explicit App Store build number
./scripts/build_release_archive.sh --build-number 4

# Build with explicit version and build number
./scripts/build_release_archive.sh --marketing-version 1.0 --build-number 4

# Deliberately submit an internal-only TestFlight build with an App Store
# Connect API key kept outside the repository.
./scripts/build_release_archive.sh \
  --upload-testflight \
  --api-key-path /secure/path/AuthKey_ABC123.p8 \
  --api-key-id ABC123 \
  --api-key-issuer-id YOUR-ISSUER-ID
```

**What it does:**
- Generates the Xcode project from `project.yml`
- Archives the Release build for `generic/platform=iOS`
- Overrides `CURRENT_PROJECT_VERSION` with a unique build number by default
- Runs `scripts/tests/validate_testflight_archive.sh` on the finished archive
- Validates version/build overrides, signing, architecture, launch assets, privacy manifest, and forbidden telemetry artifacts
- With `--upload-testflight`, exports with `app-store-connect` settings and submits an internal-only TestFlight build using the supplied API key

The dormant GitHub Actions delivery path runs this command only after a
successful push to `dev-testflight` when that automatic trigger is enabled;
see [internal TestFlight delivery](../docs/development/testflight-delivery.md).

### `validate_testflight_archive.sh` — Validate Archive Contents

Validates the app bundle inside an `.xcarchive` before you upload it.

```bash
# Validate the default archive path
./scripts/tests/validate_testflight_archive.sh

# Validate a specific archive
./scripts/tests/validate_testflight_archive.sh ./build/Plinx.xcarchive
```

**What it checks:**
- expected bundle identifier, `CFBundleShortVersionString`, and `CFBundleVersion`
- iOS platform, deployment target, arm64 executable, and valid signature
- `UILaunchStoryboardName` is present
- The compiled launch storyboard exists in the app bundle
- `PrivacyInfo.xcprivacy` exists in the app bundle
- `Assets.car` exists in the app bundle
- no Sentry bundle or obvious telemetry/secret marker is embedded

### App Store Screenshot Validation

`scripts/capture_app_store_screenshots.sh` generates the Xcode project, builds
the app once, starts the credential-free Plex and Youtarr fixture service,
resets the simulators, and captures the seven production surfaces. It validates
fixture density and artwork geometry before building. These deterministic
images stay under `screenshots/fixtures/app-store/`; they are not public
release media:

```bash
./scripts/capture_app_store_screenshots.sh
./scripts/capture_app_store_screenshots.sh --only home,youtarr
./scripts/tests/validate_app_store_screenshots.sh screenshots/fixtures/app-store
```

For that fixture directory, the validator requires exactly 14 opaque PNG files:

- seven iPhone 6.9-inch files at `1320x2868` portrait;
- seven iPad 13-inch files at `2732x2048` landscape.

The fixture service supplies data and original abstract artwork only. It does
not replace the app UI. The capture profile permits PG movies and TV-PG
television, excludes unrated content, and includes an Other Videos Home row
with landscape thumbnails. The `--only` form keeps the existing validated
inventory and refreshes only the named production screens.

Use `scripts/capture_release_screenshots.sh` and the private curated Plex
selection for public release media, then validate the promoted 22-file
`screenshots/app-store/` inventory with `--require-tvos`. Use
`scripts/release/flatten_screenshot_alpha.sh INPUT.png OUTPUT.png` only for an
individual manual diagnostic capture.

### `build_compliance_bundle.sh` — Package Corresponding Source

Creates the release's corresponding-source bundle: a `git archive` of the
current Plinx commit (which already contains the absorbed Strimr code), a copy
of `docs/release/open-source-compliance.md`, and `SOURCE-MANIFEST.txt`. The
manifest names the Plinx commit, the absorbed Strimr base from
`config/release-dependencies.env`, and every remote Swift package with its
exact pin from `PlinxApp/project.yml`. Swift Package Manager fetches those
packages as source.

Run it only from a clean, committed release checkout. It refuses a dirty tree
and any remote package without an exact `revision` or `exactVersion`:

```bash
./scripts/build_compliance_bundle.sh               # writes build/compliance/
./scripts/build_compliance_bundle.sh /path/to/dir  # custom output directory
```

`scripts/tests/test_tooling_contracts.sh` exercises both refusals and the
manifest in a throwaway repository.

---

### `docs_guard.sh` — Validate Repo Documentation Contracts

Runs the repository documentation guard locally.

```bash
./scripts/docs_guard.sh
```

**What it checks:**
- required `docs/` files exist
- legacy path references are not reintroduced
- duplicate instruction-style references are not reintroduced outside `AGENTS.md`
- the retired Strimr pairing machinery (sibling checkout paths, pin and seam
  keys, the old verifiers) does not return outside the historical records in
  `docs/maintenance/`
- `config/release-dependencies.env` records a valid absorbed Strimr base, and
  current Swift package revisions are not copied into `docs/`
- structural/code changes in PRs are paired with `AGENTS.md` or `docs/` updates

---

## Available Simulators

To see available iOS simulators:

```bash
xcrun simctl list devices available
```

Or just run a script with an invalid name—it will show the available options.

---

## Requirements

- The Xcode version in `PlinxApp/project.yml` (`options.xcodeVersion`), with
  its iOS and tvOS SDKs and simulator runtimes; the
  [current dependencies](../docs/maintenance/current-dependencies.mdx) page
  shows the value
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (used by build scripts)

## Source And Package Dependencies

A clone of this repository is the whole source tree; no other checkout is
needed. The app targets compile the Plinx app layer, `PlinxApp/Core`,
`PlinxApp/Platform/<platform>`, and the local `PlinxCore` and `PlinxUI`
packages. AetherEngine, GRDB, and SwiftAssRenderer are pinned exactly in
`PlinxApp/project.yml`. No crash-reporting or analytics package is linked.

## Troubleshooting

**Simulator not found:**
```
xcrun simctl list devices available | grep "iPhone 16"
# Adjust device name in script call if needed
```

**Build fails with missing symbols:**
```
./scripts/clean.sh
./scripts/run_iphone_sim.sh
```

**Simulator won't boot:**
```
xcrun simctl erase <device-udid>  # Full reset
./scripts/run_iphone_sim.sh       # Try again
```

---

## UI Testing Workflow

Run logic tests before every commit:

```bash
# Run all logic tests (fast, no simulator)
./scripts/ui_tests.sh

# Run snapshot tests (requires iPhone 15 simulator)
./scripts/ui_tests.sh --snapshots
```

**First time snapshot testing:**

```bash
# 1. Boot iPhone 15 simulator (or let ui_tests.sh do it)
# 2. Record baselines
./scripts/ui_tests.sh --record

# 3. Commit the generated __Snapshots__/ folder
git add Packages/PlinxUI/Tests/PlinxUITests/__Snapshots__/
git commit -m "test: record PlinxUI snapshot baselines"

# 4. Future runs will compare against these baselines
./scripts/ui_tests.sh --snapshots
```

See [docs/development/ui-testing.md](../docs/development/ui-testing.md) for test layer documentation.

---

## Integration with CI/CD

These scripts can be used in CI pipelines:

```yaml
# Example: GitHub Actions
- name: Build Plinx for iOS Simulator
  run: cd /path/to/Plinx && ./scripts/build_only.sh
```

For CI, consider:
- Pre-installing the iOS Simulator runtime
- Using `build_only.sh` (no GUI simulator needed for pure builds)
- Caching the shared `PLINX_XCODE_DERIVED_DATA_PATH` and SwiftPM scratch roots between runs

---

### `xcode_cloud_monitor.py` — Monitor And Manage Xcode Cloud

Reads recent Xcode Cloud build runs and structured failure issues through
App Store Connect. Explicit workflow-path, enable/disable, and build-start
operations are supported with a dry run by default and require `--apply` to
change Xcode Cloud. The `.p8` key and local config must remain outside the
repository.

```bash
./scripts/xcode_cloud_monitor.py
./scripts/xcode_cloud_monitor.py --details
./scripts/xcode_cloud_monitor.py --details --json --fail-on-failure
```

See [Xcode Cloud monitoring and management](../docs/development/xcode-cloud-monitoring.md)
for secure setup, management commands, and scheduled-monitor guidance.
