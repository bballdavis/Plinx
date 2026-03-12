# Development Setup

This guide covers building and running Plinx locally for development.

## Prerequisites

- macOS 14 or later
- Xcode 16 or later
- Homebrew

## Initial Setup

1. **Clone the repository with submodules:**
   ```bash
   git clone --recursive https://github.com/bballdavis/Plinx.git
   cd Plinx
   ```

2. **Install XcodeGen:**
   ```bash
   brew install xcodegen
   ```

3. **Generate the Xcode project:**
   ```bash
   cd PlinxApp
   xcodegen generate
   ```

4. **Open the project in Xcode:**
   ```bash
   open Plinx.xcodeproj
   ```

## Building and Running

### Build for Simulator

From Xcode, select the `Plinx-iOS` scheme and choose an iPhone or iPad simulator as the target, then build and run.

To build from the command line:
```bash
cd PlinxApp
xcodebuild build -project Plinx.xcodeproj -scheme Plinx-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Run Tests

See [TESTING.md](TESTING.md) for comprehensive testing instructions, including unit tests, UI tests, and live tests with Plex credentials.

## Project Structure

- **PlinxApp/** — Main app target, views, adapters, decorators
  - `App/` — App entry point and composition root
  - `Views/` — SwiftUI views for all screens (Home, Library, Settings, etc.)
  - `ViewModels/` — View model logic
  - `Adapters/` — Bridges between Plinx and Strimr (safety, playback, downloads)
  - `Decorators/` — Reusable view modifiers and wrappers
  
- **Packages/PlinxCore/** — Core safety logic, haptics, audio
  - `Sources/SafetyInterceptor.swift` — Content rating filtering
  - `Sources/HapticManager.swift` — Haptic feedback
  - `Sources/AudioManager.swift` — Sound effects
  
- **Packages/PlinxUI/** — Liquid Glass design system and reusable components
  - `Sources/LiquidGlassButton.swift` — Frosted glass button
  - `Sources/PlinxTheme.swift` — Theme system (colors, typography, springs)
  - `Sources/BabyLock.swift` — Touch lock overlay
  
- **Packages/StrimrEngine/** — Vendored Strimr media engine
  
- **vendor/strimr/** — Strimr submodule (checked out to `plinx-patches` branch)

## Strimr Integration

Plinx uses the `plinx-patches` branch of Strimr, which includes Plinx-specific enhancements on top of upstream Strimr:

- Clip and video library support
- Download quality selection
- Library browse improvements (landscape layout, long-press, pagination)
- Media detail enrichment (title logos, external ratings)
- Watch status optimistic updates
- Volume control enforcement
- Collections opt-in behavior
- Authentication branding

To update Strimr to the latest upstream changes:

```bash
cd vendor/strimr
git fetch origin
git rebase origin/main plinx-patches
cd ../..
```

Always test thoroughly after rebasing, as main may have breaking changes. See [CI_WORKFLOW_EXPLAINED.md](CI_WORKFLOW_EXPLAINED.md) for CI/CD details.

## Code Generation

The Xcode project is generated from `project.yml` using XcodeGen. If you modify dependencies, build settings, or schemes, update `project.yml` and regenerate:

```bash
cd PlinxApp
xcodegen generate
```

The generated `Plinx.xcodeproj` is gitignored and not committed. CI regenerates it on each build.

## Troubleshooting

**Build fails with "Missing package" errors:**
- Make sure you cloned with `--recursive` to fetch the Strimr submodule
- Run `git submodule update --init --recursive` if the submodule is missing

**XcodeGen not found:**
- Install via Homebrew: `brew install xcodegen`

**Simulator not appearing:**
- Xcode may need to be restarted after installing a new Xcode version
- Try opening Xcode and going to Device and Simulators to create/reset a simulator

**Code generation mismatch:**
- Run `xcodegen generate` again to regenerate the project file
- Ensure `project.yml` is up to date with your changes
