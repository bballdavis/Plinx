# CI/CD Workflow Explanation

## Current Setup

The Plinx CI/CD pipeline enforces **code review and testing BEFORE changes reach main**.

### Build Workflow

**Triggers:** PRs to main, manual workflow dispatch

**Jobs:**

#### swift-packages - Swift Package Tests
1. Test PlinxCore with code coverage
2. Test PlinxUI
3. Enforce 90%+ coverage on SafetyInterceptor.swift, MathGate.swift

#### xcode-build-and-test - Xcode Build and Unit Tests
1. Install XcodeGen
2. Generate Xcode project via xcodegen generate
3. Build Plinx-iOS for simulator
4. Run all unit tests (Plinx-iOS-UnitTests)

Note: UI tests and live tests requiring Plex credentials are not run in CI. Run them locally before submitting a PR. See TESTING.md.

## Running CI Manually

    gh workflow run build.yml --ref your-branch

## Troubleshooting

Build passed locally but fails in CI:
- CI uses macos-latest; verify Xcode/Swift versions match
- xcodeproj is gitignored; CI regenerates it - keep project.yml up to date
- Use workflow_dispatch to run CI against your branch before opening a PR
