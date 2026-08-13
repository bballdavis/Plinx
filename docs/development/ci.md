# CI

## Pinned Release Toolchain And Dependencies

CI uses macOS 26, Xcode 26.5, the exact Strimr sibling commit in
`config/release-dependencies.env`, and the exact AetherEngine revision in
`PlinxApp/project.yml`. Dependency checkout or resolution failure is fatal; do
not restore branch-based or `|| true` dependency fetches.

The iOS destinations are pinned to dedicated iPhone 17 Pro and iPad Pro
13-inch simulators on iOS 26.5. CI downloads the iOS 26.5 runtime when it is
absent, then creates those named devices before building. When changing Xcode,
update `.xcode-version`, the workflow, the test documentation, and simulator
runtime together.

## Build Workflow

Xcode Cloud is currently the primary Apple-platform CI service. Automatic
GitHub runs of `.github/workflows/build.yml` are paused to avoid consuming
GitHub-hosted macOS minutes. The workflow remains available through manual
dispatch for deliberate parity checks; its TestFlight delivery job is dormant
because that job still requires a push to `dev-testflight`.

The separate `.github/workflows/xcode-project.yml` workflow is still automatic.
It runs on an Ubuntu runner when app project inputs change, builds the pinned
XcodeGen release, regenerates `PlinxApp/Plinx.xcodeproj`, and fails if the
checked-in deployment mirror differs. It also checks out the pinned Strimr
revision because the generated project contains references to that sibling
source tree. The XcodeGen build directory is cached between runs; this check
does not compile Plinx, start a simulator, or consume a macOS runner.

See [Xcode Cloud monitoring and management](xcode-cloud-monitoring.md) for the
local App Store Connect client, checked-in project requirement, credential
boundary, explicit management operations, and scheduled monitoring setup.

Xcode Cloud must use the checked-in `PlinxApp/Plinx.xcodeproj`, Xcode 26.5,
and the shared `Plinx-iOS` and `Plinx-tvOS` schemes. Its post-clone script
fetches and verifies the exact pinned sibling Strimr source before a build or
archive action begins.

The checked-in deployment mirror intentionally includes both build schemes at
`PlinxApp/Plinx.xcodeproj/xcshareddata/xcschemes/Plinx-iOS.xcscheme` and
`PlinxApp/Plinx.xcodeproj/xcshareddata/xcschemes/Plinx-tvOS.xcscheme` so Xcode
Cloud can use both platform build plans. Regenerate them from
`PlinxApp/project.yml` with XcodeGen whenever either scheme definition changes.

When manually dispatched, it enforces:

- documentation and repository-structure guardrails
- the full Plinx↔Strimr contract after checking out the configured branch at
  the exact pinned commit
- `PlinxCore` package tests, including safety behavior
- `PlinxUI` package tests
- deterministic checked-in Xcode project verification
- iPhone and iPad app builds, including compilation of app unit/UI test targets

Use the same portable freshness check locally with:

```bash
./scripts/generate_xcodeproj.sh --check-portable
```

The existing `--check` mode additionally asks Xcode to normalize the generated
shared schemes and therefore remains macOS-only.

Before the pause, pull requests targeting `dev` or `main` and pushes to `dev`
or `dev-testflight` ran these verification jobs automatically. Only a push to
`dev-testflight`, after every check passed, submitted an internal-only
TestFlight build. Restore those triggers deliberately if GitHub-hosted Apple
CI or GitHub-based TestFlight delivery becomes necessary again.

See [TestFlight delivery](testflight-delivery.md) for the one-time App Store
Connect and GitHub secret setup, scope, and failure handling.

## Documentation Workflow

`.github/workflows/docs.yml` runs the documentation tests, TypeScript
type-check, and production Docusaurus build for pull requests targeting `dev`
or `main`. Every push to `main` rebuilds the same site and deploys it to GitHub
Pages.

The workflow uses an Ubuntu runner and deploys only after a successful build.
Generated image equality is not a required CI gate; visual asset review and the
branding generator remain available for deliberate branding changes.
The site reads its current dependency status at build time from the pinned
configuration, so deployment does not move or resolve any dependency.

## Docs Guard

CI includes a documentation guard job that verifies:

- the required `docs/` files exist
- obsolete path references are not reintroduced
- duplicate instruction-style references are not reintroduced outside `AGENTS.md`
- PRs that change code, scripts, workflows, or key root files also update repository guidance
- the Docusaurus source and required user/maintenance entry points exist
- current Strimr revisions are not copied into pairing narrative pages

The job installs `ripgrep` explicitly before running the guard so it does not
depend on the default macOS runner image.

Use the same validation locally with:

```bash
./scripts/docs_guard.sh
```

## Package Tests

CI runs:

```bash
swift test \
  --package-path Packages/PlinxCore \
  --scratch-path "$RUNNER_TEMP/plinx-swiftpm/PlinxCore"
swift test \
  --package-path Packages/PlinxUI \
  --scratch-path "$RUNNER_TEMP/plinx-swiftpm/PlinxUI"
```

Safety-critical behavior remains part of the package test suite. CI does not
parse generated coverage reports or enforce a tool-specific percentage gate.

## App Build And Unit Tests

CI also:

1. installs XcodeGen
2. regenerates the checked-in Xcode project and fails on drift
3. installs/verifies the pinned iOS runtime and creates iPhone/iPad devices
4. builds `Plinx-iOS` for both simulator form factors
5. runs the unit and UI suites on both destinations

The iPhone and iPad jobs intentionally share one `$RUNNER_TEMP/plinx-derived-data`
root. The builds run sequentially, so they can reuse package checkouts and
compiler artifacts instead of creating one SourcePackages tree per device.

The workflow creates a local branch matching the configured exact commit only
inside its disposable clone, then runs:

```bash
./scripts/verify_strimr_integration_contract.sh --full
```

This is a read-only contract check. It confirms the sibling is clean, the
branch and pin match `config/release-dependencies.env`, the configured upstream
base is an ancestor, the downstream stack is linear, and the source seams that
Plinx compiles still exist. It never pushes, rebases, or otherwise mutates a
remote branch.

## What CI Does Not Cover By Default

- live Plex-dependent UI smoke
- live parity checks that require local credentials
- TestFlight builds for pull requests, manual dispatches, `main`, or release tags
- external TestFlight distribution or App Store submission

Run those locally when the change affects playback, real-data rendering, safety filtering against live content, or release packaging.

## Manual Trigger

```bash
gh workflow run build.yml --ref your-branch
```

This command consumes GitHub Actions minutes. Use it only when a GitHub-side
parity run is intentional.

## When CI Docs Must Change

Update this file in the same PR when changing:

- workflow jobs or sequencing
- TestFlight delivery triggers, signing, or upload behavior
- enforced test scope
- docs-guard rules
- required branch pairing or dependency assumptions that CI relies on
