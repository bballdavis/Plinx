# Development Setup

This guide covers local development, project generation, and the sibling dependency layout that Plinx expects.

## Prerequisites

- macOS 14 or later
- Xcode 26 or later
- Homebrew

## Initial Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/bballdavis/Plinx.git
   cd Plinx
   ```

2. Clone sibling dependencies:

   ```bash
   cd ..
   git clone https://github.com/bballdavis/strimr.git
   git -C strimr checkout plinx-patches
   cd Plinx
   ```

   If you are working on Plinx `dev`, switch the sibling Strimr checkout to
   `dev-plinx` and verify it matches the exact revision in
   `config/release-dependencies.env`. See `docs/development/branch-pairing.md`.

3. Install XcodeGen:

   ```bash
   brew install xcodegen
   ```

4. Generate the Xcode project:

   ```bash
   cd PlinxApp
   xcodegen generate
   ```

5. Open the project:

   ```bash
   open Plinx.xcodeproj
   ```

## Build And Run

### From Xcode

Select the `Plinx-iOS` scheme and an iPhone or iPad simulator, then build and run.

### From The Command Line

```bash
cd PlinxApp
xcodebuild build \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Or use the repo scripts:

```bash
./scripts/build_only.sh
./scripts/run_iphone_sim.sh
```

## Project Generation Rules

- Treat `PlinxApp/project.yml` as the source of truth.
- Treat the generated `Plinx.xcodeproj` as disposable local output.
- If you change targets, dependencies, resources, or build settings, regenerate the project.

```bash
cd PlinxApp
xcodegen generate
```

## Testing

Use `docs/development/testing.md` as the canonical test index and `docs/development/ui-testing.md` for snapshot/UI strategy details.

## Troubleshooting

### Missing package or source errors

- Verify the sibling `../strimr` directory exists and is on the expected paired branch.
- Resolve packages after changing the pinned AetherEngine revision.
- Verify the Strimr checkout is on the expected paired branch.
- Regenerate the Xcode project after dependency or target changes.

### XcodeGen not found

```bash
brew install xcodegen
```

### Simulator issues

- Restart Xcode after installing a new version.
- Recreate or reset the simulator in Devices and Simulators if needed.

### Behavior mismatch after a build change

Remember that the app target compiles sibling `../strimr` sources directly. A runtime change may live in Strimr even if the local wrapper package looks correct.
