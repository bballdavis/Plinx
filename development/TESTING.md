# Testing & Quality Assurance

Plinx maintains high standards for safety-critical logic and UI consistency.

## Unit Testing
We aim for **100% coverage** on safety-critical components:
- `SafetyInterceptor`: Label and rating filtering logic.
- `MathGate`: Parental challenge validation.

### Running Tests
You can run tests via Xcode (Cmd+U) or via the terminal using SwiftPM:

```bash
# Test Core logic
swift test --package-path Packages/PlinxCore

# Test UI logic
swift test --package-path Packages/PlinxUI
```

## Snapshot Testing
We use visual verification to ensure the "Liquid Glass" UI remains consistent across different iPhone and iPad display sizes. Snapshot artifacts are stored in the `PlinxUI` package tests.

```bash
# Snapshot assertions
./scripts/ui_tests.sh --snapshots

# Baseline recording (temporarily enable `isRecording = true` in snapshot setUp)
./scripts/ui_tests.sh --record
```

## Primary Device Targets
Default testing devices should be:
- **iPhone 17** (current default simulator target used by scripts in this repository).
- **iPad (10th generation)** (targets the largest kid-friendly screen that must remain responsive).
These are the devices we emphasize in both local debugging and CI simulations when possible.

## Live UI Smoke Tests (Playwright-style)

Use app-level XCUITests to validate real render behavior when connected to a live Plex server.

```bash
./scripts/ui_tests.sh --live
```

### Live Plex Credentials (YAML)
To run real-server assertions, configure a `test_creds.yaml` file in the project root (copied from `test_creds.yaml.example`):

- `PLINX_PLEX_SERVER_URL`: Your Plex server address
- `PLINX_PLEX_TOKEN`: Your auth token

The `scripts/ui_tests.sh` runner automatically loads this file. If missing, live rendering assertions are skipped while basic launch smoke tests still run.

## Mocking
To ensure a fast developer feedback loop, use the `MockPlexServer` and `MockPlexClient` during local development on the macOS simulator. This avoids the need for a live Plex server during UI work.

## CI/CD
Every pull request is automatically verified via GitHub Actions:
- **Build & Test**: Verifies compilation and runs all unit tests.
- **Coverage Check**: Blocks merges if coverage on `SafetyInterceptor.swift` or `MathGate.swift` falls below 100%.
