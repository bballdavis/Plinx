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

## Primary Device Targets
Default testing devices should be:
- **iPhone 16 Pro** (it represents the latest high-end hardware for the Liquid Glass experience).
- **iPad (10th generation)** (targets the largest kid-friendly screen that must remain responsive).
These are the devices we emphasize in both local debugging and CI simulations when possible.

## Mocking
To ensure a fast developer feedback loop, use the `MockPlexServer` and `MockPlexClient` during local development on the macOS simulator. This avoids the need for a live Plex server during UI work.

## CI/CD
Every pull request is automatically verified via GitHub Actions:
- **Build & Test**: Verifies compilation and runs all unit tests.
- **Coverage Check**: Blocks merges if coverage on `SafetyInterceptor.swift` or `MathGate.swift` falls below 100%.
