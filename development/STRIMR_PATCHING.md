# Strimr Patching Workflow

Plinx maintains a patched version of Strimr (`wunax/strimr`) for kid-safe customizations. Since we don't have push access to the upstream repository, we maintain a local `plinx-patches` branch that contains all Plinx-specific modifications.

## Branch Strategy

- **`main`** — Upstream Strimr (read-only, fetch-only)
- **`plinx-patches`** — Local branch with Plinx customizations (our working branch)

The `.gitmodules` file is configured to track `plinx-patches`, so cloning or updating this repo automatically checks out the patched version.

## Workflow

### 1. Viewing Current Patches

```bash
cd vendor/strimr
git log --oneline main..HEAD
# Shows all commits in plinx-patches that are NOT in upstream main
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
git push fork plinx-patches
```

## Important Notes

- ⚠️ **Do not manually switch branches in `vendor/strimr`** — the parent Plinx repository expects `plinx-patches`
- ✅ Always rebase patches on upstream `main` before adding new work
- 📝 Use clear, descriptive commit messages with `feat(plinx):`, `fix(plinx):`, etc. prefixes
- 🔄 If upstream has breaking changes, update patches and test thoroughly before committing

## Patch History

Check what we've patched compared to upstream:

```bash
cd vendor/strimr

# Show all patches
git log --oneline main..plinx-patches

# Show detailed diffs for all patches
git diff main..plinx-patches

# Show just the summary
git shortlog main..plinx-patches
```

## CI/CD Considerations

- The Plinx CI will always use `plinx-patches` from `vendor/strimr`
- Builds will fail if patches conflict with Strimr updates
- Test locally before committing: `./scripts/build_only.sh`
