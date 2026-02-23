# Plinx Build & Run Scripts

Convenient shell scripts for building and running the Plinx iOS app on the simulator, plus UI/logic tests.

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

### `run_iphone_sim.sh` — Build, Install & Run

Generates the Xcode project, builds the app, and launches it on a simulator.

```bash
# Run on iPhone 16 Pro Max (default)
./scripts/run_iphone_sim.sh

# Run on a specific device
./scripts/run_iphone_sim.sh "iPhone 15"
```

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

```bash
# Build for iPhone 16 Pro Max (default)
./scripts/build_only.sh

# Build for a specific device
./scripts/build_only.sh "iPhone 15"
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
