# Strimr Patching Workflow

Plinx vendors a patched version of Strimr (`wunax/strimr`) with kid-safe customizations. Since we don't have push access to the upstream repository, we maintain a local `strimr-patched` branch that contains all Strimr modifications for Plinx.

## Branch & Commit Strategy

- **Submodule Pinning**: `vendor/strimr` is pinned to a specific commit (currently `9a84bd4...`) that includes all Plinx patches
- **`main` (remote)** — Upstream Strimr (upstream-only, read-only)
- **`strimr-patched` (local)** — Your working branch with patches (stays on your machine)

The `.gitmodules` file pins `vendor/strimr` to a specific commit, so when someone clones Plinx, they automatically get the patched version without needing `strimr-patched` to exist on the remote. The local `strimr-patched` branch is for your development work only.

## Workflow

### 1. Viewing Current Patches

```bash
cd vendor/strimr
git log --oneline main..HEAD
# Shows all commits in strimr-patched that are NOT in upstream main
```

### 2. Syncing with Upstream

To pull the latest changes from the upstream Strimr `main` branch:

```bash
cd vendor/strimr

# Fetch latest upstream
git fetch origin main

# Rebase patches on top of the latest upstream
git rebase origin/main

# If conflicts occur, resolve them and continue
git rebase --continue
```

### 3. Adding a New Patch

Make your changes directly on the `plinx-patches` branch:

```bash
cd vendor/strimr

# Make your edits
# ... edit files ...

# Stage and commit
git add .
git commit -m "feat(plinx): describe your change"

# The change is automatically part of plinx-patches
```

### 4. Removing or Amending Patches

```bash
cd vendor/strimr

# List recent commits
git log --oneline -10

# Amend the most recent commit
git commit --amend

# Or rebase to modify older commits
git rebase -i main
```

### 5. Pushing Changes (For Repository Maintainers)

If you gain push access to a personal fork, you can push the patched branch:

```bash
cd vendor/strimr

# Add your fork as a remote
git remote add fork https://github.com/YOUR_USERNAME/strimr.git

# Push the patches branch
git push fork strimr-patched
```

### 6. Updating the Submodule Pin

When you have new patches and want to publish them in Plinx:

```bash
# Make sure patches are committed on strimr-patched
cd vendor/strimr
git log -5

# Go back to main Plinx
cd ../..

# Update the submodule pin in git
git add vendor/strimr
git commit -m "chore(strimr): update to latest patches (commit: abcd1234...)"
git push origin main
```

## Important Notes

- ⚠️ **Do not manually switch branches in `vendor/strimr`** — the parent Plinx repository expects `strimr-patched`
- ✅ Always rebase patches on upstream `main` before adding new work
- 📝 Use clear, descriptive commit messages with `feat(plinx):`, `fix(plinx):`, etc. prefixes
- 🔄 If upstream has breaking changes, update patches and test thoroughly before committing
- 📌 The submodule is pinned to a commit, not a branch. This means cloners get the patched version automatically
- ⚙️ Since `strimr-patched` doesn't exist on the remote, you manage versions by updating the submodule commit pin

## Patch History

Check what we've patched compared to upstream:

```bash
cd vendor/strimr

# Show all patches
git log --oneline main..strimr-patched

# Show detailed diffs for all patches
git diff main..strimr-patched

# Show just the summary
git shortlog main..strimr-patched
```

## CI/CD Considerations

- Plinx CI uses the pinned commit from `vendor/strimr` — reproducible builds always get the same version
- Builds will fail if patches conflict with upstream updates
- Test locally before committing: `./scripts/build_only.sh`
- To upgrade Strimr with new patches: update submodule commit on `strimr-patched`, then pin in main
