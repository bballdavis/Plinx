# Strimr Patching Workflow

Plinx uses a sibling checkout of our patched Strimr fork with kid-safe customizations. We maintain patches as commits on a dedicated branch in that fork.

## How It Works

- **`../strimr`** is the canonical local checkout of `bballdavis/strimr`, kept on the `plinx-patches` branch
- **`plinx-patches`** is our working branch — git history *is* the patch series; no numbered patch files needed
- `origin` → `https://github.com/bballdavis/strimr.git` (our fork, push here)
- `upstream` → `https://github.com/wunax/strimr.git` (wunax upstream, pull-only)
- Plinx reads Strimr directly from the sibling checkout, so there is only one local working tree to keep in sync

## Common Tasks

### View Current Plinx Patches

```bash
cd ../strimr
git log --oneline upstream/main..HEAD
```

### Add a Patch

```bash
cd ../strimr
# Make your edits, then:
git add .
git commit -m "feat(plinx): description"
git push origin plinx-patches
```

### Amend or Reorder Commits

```bash
cd ../strimr
git rebase -i upstream/main
git push origin plinx-patches --force-with-lease
```

### Sync with Upstream

```bash
cd ../strimr
git fetch upstream
git rebase upstream/main
# Resolve any conflicts, then:
git push origin plinx-patches --force-with-lease

# Sync fork's main branch too:
git checkout main
git merge upstream/main
git push origin main
git checkout plinx-patches
```

### Open a PR to Upstream (generic fix)

1. Create a feature branch off `main` in the fork:
   ```bash
   cd ../strimr
   git checkout main
   git checkout -b fix/my-generic-fix
   # Commit the generic change
   git push origin fix/my-generic-fix
   ```
2. Open a PR from `bballdavis/strimr:fix/my-generic-fix` → `wunax/strimr:main` on GitHub.
3. Once merged, sync (see "Sync with Upstream" above) and rebase `plinx-patches`.

## Important Notes

- ✅ Keep `../strimr` on `plinx-patches` for all Plinx app builds.
- ✅ Keep fork `main` fast-forwarded to `upstream/main`; use `main` for upstream PR branches.
- ✅ Rebase `plinx-patches` onto `upstream/main` when syncing upstream changes.
- 📌 Version management happens in the fork branch itself; Plinx no longer pins a second local copy.

## Checking What We've Patched

```bash
cd ../strimr
git diff main..HEAD          # See all patch diffs
git shortlog main..HEAD      # See summary by author
```

## Testing Patches

```bash
./scripts/build_only.sh      # Quick build test
./scripts/ui_tests.sh        # Full test suite
```

## Before Building

Ensure `../strimr` is on the correct branch with no uncommitted changes:

```bash
cd ../strimr
git checkout plinx-patches
git pull origin plinx-patches  # Sync to latest remote tip (optional)
git status                     # Verify clean working tree
```

All build and test scripts build from local files only. They do not manage git state for you.
