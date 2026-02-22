# Plinx Build & Run Scripts

Convenient shell scripts for building and running the Plinx iOS app on the simulator.

## Scripts

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
