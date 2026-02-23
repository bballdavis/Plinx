# Strimr Integration Workflows

This document explains the two GitHub Actions workflows that automate Strimr integration and continuous upstream synchronization.

## Quick Reference

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **Weekly Upstream Sync** | Mondays 09:00 UTC or manual | Keep patches aligned with Strimr `main` branch |
| **Strimr Major Release** | Manual via workflow_dispatch | Orchestrated integration of breaking changes |

---

## Weekly Upstream Sync

**Location**: `.github/workflows/upstream-sync.yml`

### What It Does
1. Fetches latest Strimr `main` branch
2. Detects substantive changes (ignores screenshots/docs)
3. Regenerates atomic patches using `git diff`
4. Creates a PR with updated submodule and patches
5. All Plinx customizations are preserved automatically

### When It Runs
- **Schedule**: Every Monday at 09:00 UTC
- **Manual**: Go to **Actions** > **Weekly Upstream Sync (Strimr patches)** > **Run workflow**

### Example PR
Creates a branch `chore/strimr-upstream-sync` with:
- Updated `vendor/strimr` submodule pointer
- Regenerated `vendor/patches/strimr/*.patch` files
- Atomic patch preservation (001-004 structure maintained)

### Ignores Non-Substantive Changes
The workflow skips patch regeneration if only these types of files changed:
- Screenshots
- Documentation
- `.md`, `.png`, `.jpg` files
- `.xcassets`

Pass `force_regenerate=true` to override and regenerate anyway.

---

## Strimr Major Release Integration

**Location**: `.github/workflows/strimr-major-release.yml`

### What It Does
1. Creates a feature branch: `strimr-major-release/{commit_short}`
2. Updates submodule to specified ref (branch/tag/commit)
3. Applies all vendor patches via `./scripts/apply_vendor_patches.sh`
4. Validates the build:
   - Xcode project generation
   - StrimrEngine swift build
   - PlinxCore swift build & tests
   - PlinxUI swift build & tests
   - Plinx-iOS simulator build (Debug, iPhone 16 Pro Max)
5. Regenerates patches if conflicts detected
6. Creates a PR with comprehensive integration details

### When to Use
You control this workflow manually. Typical scenarios:
- Strimr releases a major version (v2.0.0, v3.0.0, etc.)
- Breaking changes upstream require orchestrated testing
- You want a cleaner path than the weekly cron

### How to Trigger

**Option 1: GitHub UI**
1. Go to **Actions** > **Strimr Major Release Integration**
2. Click **Run workflow**
3. Enter:
   - `strimr_ref`: Branch, tag, or commit (e.g., `main`, `v2.1.0`, `abc123def`)
   - `dry_run`: Set to `true` to skip PR creation, `false` to create it

**Option 2: GitHub CLI**
```bash
gh workflow run strimr-major-release.yml \
  -f strimr_ref=main \
  -f dry_run=false
```

**Option 3: Manual via cURL (CI/CD integration)**
```bash
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+raw" \
  https://api.github.com/repos/philipdavis/Plinx/actions/workflows/strimr-major-release.yml/dispatches \
  -d '{"ref":"main","inputs":{"strimr_ref":"main","dry_run":"false"}}'
```

### Example PR Output
Creates a branch `strimr-major-release/{new_commit}` with:
- Updated `vendor/strimr` pinned to new ref
- Regenerated patches (if needed)
- Automated testing results included
- Comprehensive PR body with integration checklist

---

## CI/CD Validation (What Gets Tested)

Both workflows run the same validation suite:

### Swift Package Builds (Non-iOS)
These use native Swift tooling and run on Linux/macOS:
- `swift build --package-path Packages/StrimrEngine`
- `swift build --package-path Packages/PlinxCore`
- `swift build --package-path Packages/PlinxUI`

### iOS Simulator Build
Requires macOS (`macos-latest` runner):
- Xcode project generation via XcodeGen
- Build for iOS Simulator (iPhone 16 Pro Max, Debug)
- Full app compilation (not just packages)

### Unit Tests
Runs for safety-critical packages:
- `PlinxCore`: Swift tests with code coverage
- `PlinxUI`: Swift tests

**Note**: GitHub Actions cannot build tvOS for hardware deployment, so:
- Swift package builds validate code compilation
- iOS simulator build validates Xcode integration
- Do not expect App Store or TestFlight builds from Actions

---

## Patch Migration Strategy

Both workflows use the **atomic patch** system to integrate Strimr changes:

### How Patches Are Created
Each workflow uses `git diff` to extract changes into 4 atomic patches:

1. **001-engine-clip-support.patch**: Core Plex clip type support
2. **002-ui-landscape-layout.patch**: 16:9 landscape layout rendering
3. **003-logging-and-filtering.patch**: OSLog hooks and hub categories
4. **004-localization-baseline.patch**: Strings and branding

### How Patches Are Applied
Both workflows run `./scripts/apply_vendor_patches.sh`, which:
1. Resets `vendor/strimr` to its submodule commit
2. Applies patches in numeric order (001 → 004)
3. Fails if a patch cannot apply cleanly
4. Outputs clear conflict messages for manual resolution

### Failure Modes
- **Patch fails to apply**: Workflow exits; manual review required to regenerate the patch
- **Build fails**: Workflow logs show compiler/linker errors; inspect for downstream changes
- **Tests fail**: Non-fatal; workflow continues but PR includes warning

---

## Workflow Inputs / Configuration

### Weekly Upstream Sync

```yaml
on:
  schedule:
    - cron: "0 9 * * 1"  # Customizable; syntax: minute hour day_of_month month day_of_week
  workflow_dispatch:
    inputs:
      force_regenerate:
        description: 'Force regenerate patches even if no changes'
        default: 'false'
```

**Cron Expression**: `0 9 * * 1` = 09:00 UTC on Mondays
- To change: Edit `.github/workflows/upstream-sync.yml`
- Format: [cron.guru](https://cron.guru)

### Strimr Major Release Integration

```yaml
workflow_dispatch:
  inputs:
    strimr_ref:
      description: 'Strimr branch/tag/commit to integrate'
      default: 'main'
      required: true
    dry_run:
      description: 'Dry run (no PR creation)'
      default: 'false'
      required: false
```

---

## Troubleshooting

### "Patch application failed"
The workflow ran `git apply` but hit conflicts in one of the 4 patches. This means:
1. The Strimr diff is incompatible with previous Plinx changes
2. You need to manually resolve the conflict in `vendor/strimr` using git
3. Regenerate the specific patch: `git diff origin/main <files> > vendor/patches/strimr/XXX-*.patch`
4. Test with `./scripts/apply_vendor_patches.sh`
5. Commit the new patch to Plinx

### "Build succeeded but tests failed"
The code compiles but one of the Swift test suites failed:
1. Check the workflow logs for test output
2. Verify that the patch didn't introduce a regression
3. Consider if upstream changes require test updates

### "iOS build failed"
Xcode compilation failed for `Plinx-iOS`. Likely causes:
1. Upstream API change requires PlinxApp code update (not just vendor patches)
2. StrimrEngine, PlinxCore, or PlinxUI have API changes
3. Check the full build log in Actions for compiler errors

### Patch regeneration produces empty diffs
If certain patches have no changes:
1. This is normal if upstream reorganized or removed earlier modifications
2. An empty `.patch` file is valid and will be skipped during apply
3. Review the diff to confirm no functionality was lost

---

## Best Practices

1. **Monitor the weekly sync**: Check PRs on Mondays to catch upstream changes early
2. **Dry-run major releases**: Use `dry_run=true` first to validate without creating a PR
3. **Test locally before merge**: The workflow validates, but human review is essential
4. **Keep patch comments clear**: Use `git diff` headers to document why each patch exists
5. **Track upstream**: Subscribe to wunax/strimr releases to anticipate breaking changes

---

## Environment & Runner Notes

- **Runner**: `macos-latest` for major release (supports iOS simulator build)
- **Runner**: `ubuntu-latest` for weekly sync (patch regeneration only)
- **Xcode**: Provided by GitHub Actions macOS image
- **Swift**: Latest from GitHub Actions macOS image
- **iOS Simulator**: iPhone 16 Pro Max, Debug configuration

---

## See Also
- [Vendor Integration Guide](./UPSTREAM_SYNC.md)
- [Patch Coordinator Script](../scripts/apply_vendor_patches.sh)
- [Atomic Patch Structure](../vendor/patches/strimr/)
