# Strimr Patching Workflow

Plinx vendors a patched version of Strimr with kid-safe customizations. Since we don't have push access to upstream, we maintain patches on a local git branch.

## How It Works

- **`vendor/strimr`** is a git submodule pinned to a specific commit
- **`plinx-strimr-patching`** is a local development branch containing all Plinx patches
- **Branch-first truth:** the branch history is canonical; numbered patch files are replay artifacts used for deterministic apply/review
- **Manifest tracking:** `vendor/Patches/strimr/manifest.yaml` is the machine-readable index of patch metadata + file coverage
- When cloning Plinx, you automatically get the patched version (submodule commit is pinned, no need for the branch to exist remotely)
- The branch stays local-only; push attempts are disabled

## Patch Governance

Run validator before and after patch updates:

```bash
./scripts/validate_vendor_patches.sh
./scripts/validate_vendor_patches.sh --strict-clean --compare-working-tree
```

Apply workflow now runs baseline validation automatically:

```bash
./scripts/apply_vendor_patches.sh
./scripts/apply_vendor_patches.sh --strict
```

Strict mode enforces a clean `vendor/strimr` tree and verifies that any working-tree vendor edits are covered by patch files.

## Common Tasks

### View Current Patches

```bash
cd vendor/strimr
git log --oneline main..HEAD
```

### Add a Patch

```bash
cd vendor/strimr
# Make your edits
git add .
git commit -m "feat(plinx): description"

# Regenerate/update numbered patch artifact(s) and manifest metadata
cd ../..
./scripts/validate_vendor_patches.sh
```

### Sync with Upstream

```bash
cd vendor/strimr
git fetch origin main
git rebase origin/main
# Resolve conflicts if any, then: git rebase --continue
```

### Amend or Reorder Patches

```bash
cd vendor/strimr
git rebase -i main
```

### Publish Patches (Update Submodule Pin)

After committing patches locally:

```bash
cd /Users/philipdavis/Repos/Plinx
./scripts/validate_vendor_patches.sh --strict-clean --compare-working-tree
git add vendor/strimr vendor/Patches/strimr
git commit -m "chore(strimr): update patches (commit abc1234)"
```

## Important Notes

- ✅ **Always rebase `plinx-strimr-patching` on upstream `main` before adding new patches**
- ⚠️ **Never manually switch branches in `vendor/strimr`** — the parent repo expects `plinx-strimr-patching`
- 🔒 Push is disabled on this branch (intentional; it's local-only)
- 📌 Version management happens by updating the submodule commit in the main Plinx repo, not by syncing the branch
- 📌 Keep `vendor/Patches/strimr/manifest.yaml` in sync with every patch file update

## Checking What We've Patched

```bash
cd vendor/strimr
git diff main..HEAD          # See all patch diffs
git shortlog main..HEAD      # See summary by author
```

## Testing Patches

```bash
./scripts/build_only.sh      # Quick build test
./scripts/ui_tests.sh        # Full test suite
```
