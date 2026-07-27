# CI

## Pinned Release Toolchain And Dependencies

CI uses macOS 15, Xcode 26.5, the exact Strimr sibling commit in
`config/release-dependencies.env`, and the exact AetherEngine revision in
`PlinxApp/project.yml`. Dependency checkout or resolution failure is fatal; do
not restore branch-based or `|| true` dependency fetches.

The iOS destinations are pinned to dedicated iPhone 17 Pro and iPad Pro
13-inch simulators on iOS 26.5. CI downloads the iOS 26.5 runtime when it is
absent, then creates those named devices before building. When changing Xcode,
update `.xcode-version`, the workflow, the test documentation, and simulator
runtime together.

## Build Workflow

The main CI workflow lives in `.github/workflows/build.yml`.

It currently enforces:

- documentation and repository-structure guardrails
- the full Plinx↔Strimr contract after checking out the configured branch at
  the exact pinned commit
- `PlinxCore` package tests with coverage enforcement for safety-critical files
- `PlinxUI` package tests
- Xcode project generation
- iPhone and iPad app builds and app unit/UI tests

## Documentation Workflow

`.github/workflows/docs.yml` runs the documentation tests, TypeScript
type-check, and production Docusaurus build for pull requests targeting `dev`
or `main`. Every push to `main` rebuilds the same site and deploys it to GitHub
Pages.

The workflow uses an Ubuntu runner and deploys only after a successful build.
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

Use the same validation locally with:

```bash
./scripts/docs_guard.sh
```

## Package Tests

CI runs:

```bash
swift test --package-path Packages/PlinxCore --enable-code-coverage
swift test --package-path Packages/PlinxUI
```

Coverage enforcement is applied to safety-critical files in `Packages/PlinxCore/Sources/PlinxCore/Safety/`.

## App Build And Unit Tests

CI also:

1. installs XcodeGen
2. generates the Xcode project
3. installs/verifies the pinned iOS runtime and creates iPhone/iPad devices
4. builds `Plinx-iOS` for both simulator form factors
5. runs the unit and UI suites on both destinations

The workflow creates a local `dev-plinx` branch at the configured exact commit
only inside its disposable clone, then runs:

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
- manual App Store upload

Run those locally when the change affects playback, real-data rendering, safety filtering against live content, or release packaging.

## Manual Trigger

```bash
gh workflow run build.yml --ref your-branch
```

## When CI Docs Must Change

Update this file in the same PR when changing:

- workflow jobs or sequencing
- enforced test scope
- docs-guard rules
- required branch pairing or dependency assumptions that CI relies on
