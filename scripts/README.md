# Plinx Build & Run Scripts

All executable scripts use Bash. They can be invoked directly from any shell,
for example `./scripts/run_ipad_sim.sh`; if launched with `zsh script.sh`, they
re-enter through Bash before resolving repository-relative paths.

Convenient shell scripts for building and running the Plinx iOS app on the simulator, plus UI/logic tests.

## Strimr Source Of Truth

Build and test scripts build from local files only. It's your responsibility to ensure the sibling `../strimr` checkout is on the correct branch and in a clean state before running any build command.

**Branch selection:**
- Working on **Plinx `main`** branch? Use **`plinx-patches`** branch in strimr:
  ```bash
  cd ../strimr
  git checkout plinx-patches
  git pull origin plinx-patches
  ```

- Working on **Plinx `dev`** branch? Use **`dev-plinx`** branch in strimr:
  ```bash
  cd ../strimr
  git checkout dev-plinx
  git pull origin dev-plinx
  ```

**Before building:**
```bash
git status                     # Verify clean working tree
```

If `../strimr` is on the wrong branch or has uncommitted changes, the build can pick up the wrong engine code. Developers are responsible for managing both local git states intentionally.

Run the pairing verifier before a combined build:

```bash
# Verify source roots and required Strimr seam symbols.
./scripts/verify_strimr_integration_contract.sh --quick

# Also require a clean sibling, exact pin, expected branch, upstream ancestry,
# and a linear downstream patch stack.
./scripts/verify_strimr_integration_contract.sh --full
```

The exact pairing and seam inventory live in
`config/release-dependencies.env`. See
[`docs/development/branch-pairing.md`](../docs/development/branch-pairing.md)
for candidate-update workflow and CI behavior.

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

Applies the pinned Strimr release patch, runs XcodeGen, and adds separate iOS
and tvOS resource phases so each product contains its asset catalog,
localizations, and privacy manifest. The iOS phase also compiles the launch
storyboard. Do not replace the target-owned phases with a shared build phase;
Xcode may then omit resources from one platform bundle.

### `strimr/run_ipad_sim.sh` — Build & Run Strimr Branch on iPad Simulator

Builds and runs the **active branch of the sibling `../strimr` checkout** on an iPad simulator. Use this to test feature branches you want to feed back upstream before they become part of Plinx.

```bash
# Default: iPad (10th generation)
./scripts/strimr/run_ipad_sim.sh

# Custom device
./scripts/strimr/run_ipad_sim.sh "iPad Pro 13-inch"
```

**Workflow:**
```bash
# Switch Strimr to the branch you want to test
cd ../strimr && git switch feat/centered-clear-logo

# Build & run it directly from Plinx scripts
cd ../Plinx && ./scripts/strimr/run_ipad_sim.sh
```

The script reports the active Strimr branch and commit hash at the start so you always know exactly what you're running. It warns if there are uncommitted changes in Strimr.

No XcodeGen required — builds directly from `Strimr.xcodeproj`.

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
```

**What it does:**
- Generates the Xcode project from `project.yml`
- Archives the Release build for `generic/platform=iOS`
- Overrides `CURRENT_PROJECT_VERSION` with a unique build number by default
- Applies the pinned Strimr patch, generates the project, and runs `scripts/tests/validate_testflight_archive.sh`
- Validates version/build overrides, signing, architecture, launch assets, privacy manifest, and forbidden telemetry artifacts

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

`scripts/tests/validate_app_store_screenshots.sh` accepts only the release inventory:

- iPhone 6.9-inch: `1320x2868` portrait or landscape inverse;
- iPad 13-inch: `2064x2752` or `2048x2732` portrait, or either landscape inverse;
- PNG files with no alpha channel.

Use `scripts/flatten_screenshot_alpha.sh INPUT.png OUTPUT.png` only after capturing fictional review content. Do not promote the legacy `screenshots/` files; they fail the current iPad-size and alpha checks.

### `build_compliance_bundle.sh` — Package Corresponding Source

Creates the release's Plinx and pinned Strimr source bundle. AetherEngine is an
exact Swift Package Manager source dependency recorded by `project.yml` and the
generated package resolution. Run only from a clean committed release checkout:

```bash
./scripts/build_compliance_bundle.sh
```

Both release scripts call `scripts/verify_release_dependency_state.sh`. It
compares the live sibling tree against the exact Strimr commit in
`config/release-dependencies.env`, preventing unrelated local dependency
changes from entering a release archive.

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

- Xcode 26.5 with the iOS 26.5 SDK and simulator runtime
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (used by build scripts)
- iOS Simulator runtime

## Local Source And Package Dependencies

Plinx compiles the paired sibling Strimr checkout directly and resolves its
player engine through Swift Package Manager:

```bash
<local repositories path>/
  Plinx/
  strimr/
```

The live app target compiles sibling `strimr/Shared` and platform feature paths.
`AetherEngine` is pinned to an exact revision in `PlinxApp/project.yml`.
Plinx excludes Strimr's Sentry-backed reporter and does not declare Sentry as a
package dependency.

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
