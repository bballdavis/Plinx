# Development Setup

This guide covers building and running Plinx locally for development.

## Prerequisites

- macOS 14 or later
- Xcode 26 or later
- Homebrew

## Initial Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/bballdavis/Plinx.git
   cd Plinx
   ```

2. **Clone sibling dependencies:**
  Plinx depends on local-path dependencies (`strimr` and `MPVKit`) checked out as sibling directories:
   ```bash
   cd ..
   git clone https://github.com/bballdavis/strimr.git
   # Choose the correct Strimr branch based on which Plinx branch you're working on:
   # For Plinx main: use plinx-patches
   git -C strimr checkout plinx-patches
   # For Plinx dev: use dev-plinx
   # git -C strimr checkout dev-plinx
   git clone https://github.com/wunax/MPVKit.git
   cd Plinx
   ```
   After cloning, your directory structure should look like:
   ```
   Parent/
   ├── Plinx/
   ├── strimr/
   └── MPVKit/
   ```

3. **Install XcodeGen:**
   ```bash
   brew install xcodegen
   ```

4. **Generate the Xcode project:**
   ```bash
   cd PlinxApp
   xcodegen generate
   ```

5. **Open the project in Xcode:**
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
  
- **../strimr/** — Sibling Strimr checkout used by the app target at build time

## Strimr Integration

Plinx uses branch-specific versions of the Strimr fork:

- **Plinx `main` branch** → Strimr `plinx-patches` branch
  - Stable Plinx-specific enhancements on upstream Strimr
  
- **Plinx `dev` branch** → Strimr `dev-plinx` branch  
  - Development branch for new features and experimental work

Plinx-specific enhancements include:
- Clip and video library support
- Download quality selection
- Library browse improvements (landscape layout, long-press, pagination)
- Media detail enrichment (title logos, external ratings)
- Watch status optimistic updates
- Volume control enforcement
- Collections opt-in behavior
- Authentication branding

To update Strimr to the latest upstream changes (depending on which branch you're on):

```bash
# If on locally on Plinx main, working with plinx-patches:
cd ../strimr
git fetch origin
git rebase origin/main plinx-patches
cd ../..

# If locally on Plinx dev, working with dev-plinx:
cd ../strimr
git fetch origin
git rebase origin/main dev-plinx
cd ../..
```

Always test thoroughly after rebasing, as main may have breaking changes. See [CI_WORKFLOW_EXPLAINED.md](CI_WORKFLOW_EXPLAINED.md) for CI/CD details.

## Code Generation

The Xcode project is generated from `project.yml` using XcodeGen. If you modify dependencies, build settings, or schemes, update `project.yml` and regenerate:

```bash
cd PlinxApp
xcodegen generate
```

The generated `Plinx.xcodeproj` is gitignored and may be regenerated locally as needed. Treat `project.yml` as the source of truth.

## Troubleshooting

**Build fails with "Missing package" errors:**
- Make sure the sibling `../strimr` and `../MPVKit` directories exist
- Verify `../strimr` is on the expected paired branch for the Plinx branch you are using

**XcodeGen not found:**
- Install via Homebrew: `brew install xcodegen`

**Simulator not appearing:**
- Xcode may need to be restarted after installing a new Xcode version
- Try opening Xcode and going to Device and Simulators to create/reset a simulator

**Code generation mismatch:**
- Run `xcodegen generate` again to regenerate the project file
- Ensure `project.yml` is up to date with your changes
- If a behavior change lives in the Strimr engine, remember the app target builds against sibling `../strimr` sources directly
