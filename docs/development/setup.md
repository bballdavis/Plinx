# Development Setup

This guide covers local development, project generation, and the sibling dependency layout that Plinx expects.

## Prerequisites

- macOS 14 or later
- The release Xcode version recorded in `.xcode-version` (newer local Xcode
  versions require their own compatibility check)
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
   git -C strimr remote add upstream https://github.com/wunax/strimr.git
   git -C strimr config remote.pushDefault origin
   git -C strimr fetch origin
   git -C strimr fetch upstream
   cd Plinx
   source config/release-dependencies.env
   git -C ../strimr switch --track "origin/$STRIMR_BRANCH"
   ./scripts/verify_strimr_integration_contract.sh --full
   ```

   `origin` is your writable fork; `upstream` is the original Strimr project.
   Fetching upstream makes comparison possible without updating the paired pin.
   If the local branch already exists, use `git -C ../strimr switch
   "$STRIMR_BRANCH"` instead. A branch head that differs from the exact pin
   needs deliberate pairing work; do not pull a newer engine into a build.

   Create the other local tracking branch when needed with
   `git -C ../strimr branch --track dev-plinx origin/dev-plinx` or
   `git -C ../strimr branch --track plinx-patches origin/plinx-patches`.
   The canonical development/stable branch roles are described in
   [branch pairing](branch-pairing.md), but the checked-out Plinx configuration
   always decides the branch and commit for verification.

3. Install XcodeGen:

   ```bash
   brew install xcodegen
   ```

4. Regenerate the checked-in Xcode project to verify the local XcodeGen output:

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

The repository scripts use Bash and can be launched directly from any shell.
Prefer the repository-relative form below; if explicitly launched with `zsh
./scripts/run_iphone_sim.sh`, the script re-enters through Bash before resolving
its repository-relative paths.

The scripts share a persistent Xcode DerivedData and SwiftPM cache under
`~/Library/Caches/Plinx` by default. They reuse those caches across destinations
and test layers; use `./scripts/clean.sh` when a full rebuild is intentional.

```bash
cd PlinxApp
source ../scripts/build_environment.sh
xcodebuild build \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH"
```

Or use the repo scripts:

```bash
./scripts/build_only.sh
./scripts/run_iphone_sim.sh
```

To verify the Apple TV target on Apple Silicon without installing a tvOS
simulator runtime, compile for a generic simulator with the supported
architecture explicitly selected:

```bash
source scripts/build_environment.sh
xcodebuild build \
  -project PlinxApp/Plinx.xcodeproj -scheme Plinx-tvOS \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
```

The pinned LibDovi simulator binary supplies arm64. An unrestricted generic
build can also request x86_64 and fail at link time; that is not a reason to
change the Strimr or AetherEngine pins. A runtime is still needed for Apple TV
interaction tests, and simulator builds do not verify distribution signing.

## Project Generation Rules

- Treat `PlinxApp/project.yml` as the source of truth.
- Treat the checked-in `Plinx.xcodeproj` as a generated deployment mirror, not
  the source of truth. It must remain in Git so Xcode Cloud can discover it.
- If you change targets, dependencies, resources, or build settings, regenerate
  and commit the project alongside `project.yml`.

```bash
cd PlinxApp
xcodegen generate
```

In a clean checkout, verify the committed mirror with:

```bash
./scripts/generate_xcodeproj.sh --check
```

## Testing

Use `docs/development/testing.md` as the canonical test index and `docs/development/ui-testing.md` for snapshot/UI strategy details.

## Documentation Site

The Docusaurus site renders a generated copy of the repository's canonical
`docs/` directory. The build also generates a documentation route from the
root `PRIVACY_POLICY.md`, without making a second policy source. From the
repository root, install and preview it with:

```bash
npm ci --prefix website
npm run start --prefix website
```

Use `npm run build --prefix website` before changing documentation navigation,
links, theme, generated dependency status, or deployment configuration.

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
