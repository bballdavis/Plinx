# CI/CD Workflow Explanation

## Current Setup

The Plinx CI/CD pipeline enforces **code review and testing BEFORE changes reach main**.

### Build Workflow (`build.yml`)

**Triggers:**
- ✅ Pull Requests to `main` (any branch can PR)
- ✅ Manual workflow dispatch (for adhoc runs)
- ❌ ~~Direct pushes to main~~ (disabled - use PRs instead)

**Steps:**
1. Checkout code with submodules
2. Install build tools (XcodeGen)
3. Generate Xcode project
4. Build Swift packages (PlinxCore, PlinxUI)
5. Build Plinx-iOS app
6. Run unit tests
7. Enforce code coverage thresholds (90%+ on safety-critical code)

### Branch Protection Rules

Currently enforced at the workflow level:
- **Branch Flow Guard** is disabled (was enforcing dev→main, but no dev branch exists)
- Main branch is protected by PR requirement at the GitHub repo settings

## Workflow

```
your-feature
    ↓
[Create PR → main]
    ↓
[CI runs: build, test, coverage checks]
    ↓
[If all pass: Ready to merge or needs review] 
[If fail: Fix code, push update, re-run CI]
    ↓
[Merge to main]
    ↓
Main is always stable and buildable
```

## Why This Works Better

**Before:** Push → main → build fails → main is broken
**After:** PR → build validation → merge only if passing → main is always green

## Running CI Manually

To manually trigger the build workflow (useful for quick checks):

```bash
gh workflow run build.yml --ref main
```

Or see available workflows:
```bash
gh workflow list
```

## Troubleshooting

**"My build passed locally but fails in CI"**
- CI runs on `macos-latest` which may differ from your local setup
- Check Swift/Xcode versions in your environment vs GitHub Actions
- Use `workflow_dispatch` to debug by running CI against your branch

**"I accidentally pushed directly to main"**
- The build workflow won't run on direct pushes anymore (by design)
- Just delete any failed workflow runs
- Going forward, use PRs for everything

## For Future: Dev Branch Strategy

If the team wants a proper staging/integration branch:
1. Create `dev` branch off current `main`
2. Re-enable `branch-flow-guard.yml`
3. Only merge feature PRs into `dev`
4. Create release PRs from `dev` → `main` periodically
5. Update `build.yml` triggers accordingly

See [UPSTREAM_SYNC.md](./UPSTREAM_SYNC.md) for related Strimr integration workflow.
