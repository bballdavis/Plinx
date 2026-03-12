# Testing Plinx

Plinx uses three layers of testing to catch regressions at different levels:

1. **Logic tests** — Swift Testing for pure functions and business logic
2. **Snapshot tests** — Compare UI component rendering across devices
3. **UI tests** — XCUITest for critical user paths (navigation, playback, settings)
4. **Live tests** — UI tests with real Plex server data (requires credentials)

## Running Tests Locally

### All Unit Tests

```bash
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" \
  -only-testing:Plinx-iOS-UnitTests \
  CODE_SIGNING_ALLOWED=NO
```

### All Swift Package Tests (PlinxCore, PlinxUI)

From the repo root:

```bash
swift test -c debug
```

This runs logic and snapshot tests without a full app build. Snapshot diffs are saved to `__Snapshots__/` directories if changes occur.

### Targeted UI Tests (Non-Live)

These run without server credentials and verify navigation/layout:

```bash
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPad (10th generation)" \
  -only-testing:Plinx-iOS-UITests/NavigationUITests \
  CODE_SIGNING_ALLOWED=NO
```

### Live UI Tests (Requires Plex Credentials)

Live tests verify rendering and behavior with real Plex server data:

```bash
cd PlinxApp
xcodebuild test \
  -project Plinx.xcodeproj \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,name=iPad (10th generation)" \
  -only-testing:Plinx-iOS-UITests/HomeScreenSectionUITests \
  -only-testing:Plinx-iOS-UITests/LiveRenderSmokeUITests \
  CODE_SIGNING_ALLOWED=NO
```

Live tests are designed to **skip** gracefully if credentials are unavailable, so they won't fail unrelated PRs.

## Configuring Live Test Credentials

1. Copy the template:
   ```bash
   cp test_creds.yaml.example test_creds.yaml
   ```

2. Edit `test_creds.yaml` and populate:
   ```yaml
   PLINX_PLEX_SERVER_URL: "http://your-plex-server:32400"
   PLINX_PLEX_TOKEN: "your-plex-auth-token"
   ```

   Or provide a Plex user email, password, and home profile PIN instead.

3. The test fixtures will automatically load credentials at runtime.

## Test Structure

### PlinxCore Tests (`Packages/PlinxCore/Tests/`)

Pure logic tests for the safety layer:

- `SafetyInterceptor` — Content rating filtering, label validation
- `PlinxRating` — Rating parsing, type detection (TV vs. movie)
- `MathGate` — Challenge generation, answer validation
- `SafetyPolicy` — Rating ceiling enforcement

Run without a simulator:
```bash
swift test
```

### PlinxUI Tests (`Packages/PlinxUI/Tests/`)

Component rendering and layout tests:

- **Logic tests** — Aspect ratio calculations, layout rules
- **Snapshot tests** — Pixel-perfect rendering of cards, buttons, and hubs across device sizes (iPhone SE, iPhone 14, iPad)
- **Component tests** — LiquidGlassButton, PlinxTheme, BabyLock behavior

Snapshot tests automatically capture baseline images in `__Snapshots__/` and flag any rendering changes.

### App Unit Tests (`PlinxApp/UnitTests/`)

Integration tests for app-specific logic:

- `SettingsManager` — Persistence and retrieval of user settings
- `HomeLibraryGrouping` — Section classification and ordering
- `DownloadThumbnailLayout` — Artwork aspect ratio detection

Run with the `Plinx-iOS` scheme.

### App UI Tests (`PlinxApp/UITests/`)

Critical user path verification:

- **Navigation** — Tab switching, screen transitions, back buttons
- **Playback** — Player launch, close button, playback controls
- **Settings** — Parental gate (math and PIN), setting changes
- **Library browsing** — Grid scrolling, sorting, filtering
- **Search** — Query submission, result interaction
- **Downloads** — Download grid, list toggle, playback

## Test Matrix (Priority)

| Feature | What to verify | Test class |
|---|---|---|
| Home rows | Movies+TV combined/split, Other Videos landscape, section order | `HomeScreenSectionUITests` |
| Library tab | Single tab bar, browse grid stability during pagination | `LibraryTabUITests` |
| Player | Launch, close, overlay visibility | `PlayerUITests` |
| Settings | Parental gate, accent color, visibility toggles | `SettingsUITests` |
| Safety | Rating filtering, blocked content state | `SafetyInterceptorTests`, `LiveRenderSmokeUITests` |
| Download layout | Poster grid, list toggle, progress bars | `DownloadThumbnailLayoutUITests` |
| Clips | Landscape cards, duration display | `ClipCardSnapshotTests` |

## Device Coverage

- **iPhone** — Compact width tests (tab bar compression)
- **iPad (10th generation)** — Regular width tests (full tab bar, 2-column browse)
- **Landscape orientation** — Responsive layout tests

## CI/CD Integration

All unit and snapshot tests run in CI on every PR. Live UI tests do not run in CI and must be run locally before submitting a PR that affects playback, settings, or safety behavior.

See [CI_WORKFLOW_EXPLAINED.md](CI_WORKFLOW_EXPLAINED.md) for the full CI/CD pipeline.
