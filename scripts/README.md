# Plinx Build & Run Scripts

Convenient shell scripts for building and running the Plinx iOS app on the simulator, plus UI/logic tests.

## Strimr Source Of Truth

Build and test scripts build from local files only. It's your responsibility to ensure `vendor/strimr` is on the correct branch and in a clean state before running any build command.

**Branch selection:**
- Working on **Plinx `main`** branch? Use **`plinx-patches`** branch in strimr:
  ```bash
  cd vendor/strimr
  git checkout plinx-patches
  git pull origin plinx-patches
  ```

- Working on **Plinx `dev`** branch? Use **`dev-plinx`** branch in strimr:
  ```bash
  cd vendor/strimr
  git checkout dev-plinx
  git pull origin dev-plinx
  ```

**Before building:**
```bash
git status                     # Verify clean working tree
```

If `vendor/strimr` is on the wrong branch or has uncommitted changes, the build will fail. This is intentional — developers are responsible for managing their local git state.

## Scripts

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

See [development/UI_TESTING_STRATEGY.md](../development/UI_TESTING_STRATEGY.md) for full documentation.

---

### `live_library_parity_tests.sh` — Run Live Browse/Recommend Parity Tests

Loads `test_creds.yaml`, injects Plex credentials into the test process, and runs:
`Plinx-iOS-UnitTests/LibraryFilteringParityLiveTests`

```bash
# Run against default simulator destination
./scripts/live_library_parity_tests.sh

# Run against a custom destination string
./scripts/live_library_parity_tests.sh 'platform=iOS Simulator,name=iPhone 17'
```

**What it does:**
- Reads `PLINX_PLEX_SERVER_URL` and `PLINX_PLEX_TOKEN` from repository-root `test_creds.yaml`
- Exports both direct and `SIMCTL_CHILD_*` env vars for simulator test propagation
- Runs targeted live parity tests and writes full logs to `/tmp/plinx_live_library_parity.log`
- Writes result bundle to `/tmp/Plinx_live_library_parity.xcresult`

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

Removes all generated and cached build files.

```bash
./scripts/clean.sh
```

**What it removes:**
- `Plinx.xcodeproj` (regenerated from project.yml on next build)
- `DerivedData/` (local Xcode artifacts)
- Plinx entries in `~/Library/Developer/Xcode/DerivedData`

**Use when:** You encounter weird build cache issues or want a fresh build.

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
- Runs `validate_testflight_archive.sh` to catch missing launch screen and privacy manifest issues locally

### `validate_testflight_archive.sh` — Validate Archive Contents

Validates the app bundle inside an `.xcarchive` before you upload it.

```bash
# Validate the default archive path
./scripts/validate_testflight_archive.sh

# Validate a specific archive
./scripts/validate_testflight_archive.sh ./build/Plinx.xcarchive
```

**What it checks:**
- `CFBundleShortVersionString` and `CFBundleVersion` are present
- `UILaunchStoryboardName` is present
- The compiled launch storyboard exists in the app bundle
- `PrivacyInfo.xcprivacy` exists in the app bundle
- `Assets.car` exists in the app bundle

---

## Available Simulators

To see available iOS simulators:

```bash
xcrun simctl list devices available
```

Or just run a script with an invalid name—it will show the available options.

---

## Requirements

- Xcode 26+ with iOS 26.2 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (used by build scripts)
- iOS Simulator runtime

## Local Dependency Mirrors

For local stability, Plinx references sibling clones of forked package repositories directly from [PlinxApp/project.yml](PlinxApp/project.yml):

```bash
/Users/philipdavis/Repos/
  Plinx/
  MPVKit/
  sentry-cocoa/
```

These are referenced via `../../MPVKit` and `../../sentry-cocoa` from the `PlinxApp` directory, which means GUI archive/distribute flows in Xcode use the same local package sources as the shell scripts once the project has been generated.

This removes dependency on cloning the package source from upstream during project generation and package resolution. It does not, by itself, eliminate all remote binary artifact downloads if the package manifests still point to release ZIPs.

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

See [development/UI_TESTING_STRATEGY.md](../development/UI_TESTING_STRATEGY.md) for test layer documentation.

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
- Caching the `DerivedData` directory between runs
