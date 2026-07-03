# CI

## Build Workflow

The main CI workflow lives in `.github/workflows/build.yml`.

It currently enforces:

- documentation and repository-structure guardrails
- `PlinxCore` package tests with coverage enforcement for safety-critical files
- `PlinxUI` package tests
- Xcode project generation
- app build and app unit tests

## Docs Guard

CI includes a documentation guard job that verifies:

- the required `docs/` files exist
- obsolete path references are not reintroduced
- duplicate instruction-style references are not reintroduced outside `AGENTS.md`
- PRs that change code, scripts, workflows, or key root files also update repository guidance

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
3. builds `Plinx-iOS` for simulator
4. runs `Plinx-iOS-UnitTests`

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
