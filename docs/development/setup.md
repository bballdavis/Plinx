# Development Setup

This guide covers local development and project generation. A single clone of
this repository is the whole source tree.

## Prerequisites

- macOS 14 or later
- The Xcode version in `PlinxApp/project.yml` (`options.xcodeVersion`; the
  [current dependencies](../maintenance/current-dependencies.mdx) page shows
  it). Newer local Xcode versions need their own compatibility check.
- Homebrew

## Initial Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/bballdavis/Plinx.git
   cd Plinx
   ```

   The media, provider, session, and player code Plinx absorbed from Strimr is
   in `PlinxApp/Core` and `PlinxApp/Platform`. No sibling checkout is needed.
   Swift Package Manager resolves AetherEngine, GRDB, and SwiftAssRenderer at
   the exact pins in `PlinxApp/project.yml` the first time Xcode opens the
   project.

2. Optional, for upstream feature reviews only: add the original Strimr project
   as a fetch-only remote. Nothing in the build reads it.

   ```bash
   git remote add upstream https://github.com/wunax/strimr.git
   git remote set-url --push upstream DISABLED
   git fetch upstream
   ```

   See [upstream Strimr provenance](../maintenance/upstream-strimr.md) for how
   to review and port upstream changes.

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

### Compile without a simulator runtime

Compiling never needs a simulator runtime. On Apple Silicon, build either
target for a generic simulator destination with the supported architecture
explicitly selected:

```bash
source scripts/build_environment.sh
xcodebuild build \
  -project PlinxApp/Plinx.xcodeproj -scheme Plinx-tvOS \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
```

Use `-scheme Plinx-iOS` with `generic/platform=iOS Simulator` for the iPhone
and iPad target. To compile the unit and UI test bundles as well, run
`xcodebuild build-for-testing` with the same destination and settings.

The pinned LibDovi simulator binary supplies arm64. An unrestricted generic
build can also request x86_64 and fail at link time; that is not a reason to
change the AetherEngine pin. Running tests, UI tests, or the app needs an
installed simulator runtime and a concrete device (`xcrun simctl list devices
available`), and simulator builds do not verify distribution signing.

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

## Entitlements

Neither app target is signed with an entitlements file. Add one only for a
capability Apple has granted to the team's App ID. Automatic signing fails for
device and archive builds when an entitlement is missing from the provisioning
profile, and simulator builds never show that failure.

### Multicast networking (Jellyfin server search)

The Jellyfin sign-in form can search the local network for servers.
`JellyfinServerDiscoveryService` sends a UDP broadcast to port 7359 from a BSD
socket. On iPhone and iPad, iOS 14 and later block that broadcast unless the app
is signed with `com.apple.developer.networking.multicast`. Apple grants this
managed entitlement only on request. Apple TV needs no entitlement.

Plinx does not have the grant yet. `JellyfinServerDiscoveryService.isSupported`
is therefore false on iOS, and the iPhone and iPad sign-in form hides **Search
local servers**. Manual server address entry is the only way to connect there.
Apple TV keeps the search. `JellyfinServerDiscoveryAvailabilityTests` covers
the iOS behavior.

To enable the search on iPhone and iPad:

1. The Apple Developer account holder requests the multicast networking
   entitlement for `com.bballdavis.plinx` from Apple.
2. After Apple grants it, enable the capability on the App ID under
   Certificates, Identifiers & Profiles (Additional Capabilities).
3. In `PlinxApp/project.yml`, give the `Plinx-iOS` target the entitlement, and
   add the compile condition that turns the search on to its existing
   `settings.base`:

   ```yaml
   entitlements:
     path: Resources/Plinx-iOS.entitlements
     properties:
       com.apple.developer.networking.multicast: true
   settings:
     base:
       SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) PLINX_MULTICAST_ENTITLEMENT"
   ```

   XcodeGen writes the entitlements file and sets `CODE_SIGN_ENTITLEMENTS`.
   Regenerate the project, then commit the entitlements file with it.
4. Flip the expectations in `JellyfinServerDiscoveryAvailabilityTests`, and
   update the Jellyfin steps in `docs/user/getting-started.md`.
5. Check a device or archive build. Run
   `codesign -d --entitlements - Plinx.app` and confirm it lists the key. Then
   confirm the search finds a server on a physical iPhone, because the
   simulator does not enforce the entitlement.

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

- Resolve packages (File > Packages > Resolve Package Versions) after a Swift
  package pin changes in `PlinxApp/project.yml`.
- Regenerate the Xcode project after dependency, target, or source-folder
  changes. A file added under `PlinxApp/Core` or `PlinxApp/Platform` is not
  compiled until the project is regenerated.

### XcodeGen not found

```bash
brew install xcodegen
```

### Simulator issues

- Restart Xcode after installing a new version.
- Recreate or reset the simulator in Devices and Simulators if needed.

### Behavior mismatch after a build change

Shared behavior usually lives in `PlinxApp/Core`, and platform screens in
`PlinxApp/Platform`. Check there before assuming a Plinx view is at fault. The
[codebase architecture](../architecture/strimr-integration.md) maps each layer.
