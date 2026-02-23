## Quick Start: Strimr Integration Automation

### 📅 Weekly Automatic Sync (Every Monday)
The `upstream-sync.yml` workflow runs automatically every Monday at 09:00 UTC to:
- Fetch latest Strimr `main`
- Regenerate atomic patches if code changed
- Create a PR automatically

**No action needed** — check your PRs on Mondays.

### 🚀 Major Release Integration (Manual)
When Strimr releases a major version, trigger the `strimr-major-release.yml` workflow:

**Via GitHub UI:**
1. Go to **Actions** tab
2. Select **Strimr Major Release Integration**
3. Click **Run workflow**
4. Enter the Strimr ref (e.g., `main`, `v2.0.0`, or a commit SHA)
5. Set `dry_run=false` to create the PR automatically

**Result:**
- Feature branch: `strimr-major-release/{new_commit_short}`
- Patches applied automatically
- Swift packages validated
- iOS simulator build tested
- PR created with full integration checklist

### 🐛 If Patches Fail
The script logs detailed conflict info. To fix:

```bash
# 1. Check which patch failed
cd vendor/strimr
git status  # See which files have conflicts

# 2. Resolve manually using git
git mergetool  # or your preferred merge tool

# 3. Regenerate just that patch
git diff origin/main <conflicted_files> > ../patches/strimr/NNN-*.patch

# 4. Test locally
cd ../..
./scripts/apply_vendor_patches.sh
```

### 📚 Full Documentation
See [development/STRIMR_WORKFLOWS.md](./STRIMR_WORKFLOWS.md) for:
- Detailed workflow explanations
- Environment/runner notes
- Troubleshooting guide
- CI/CD validation strategy

### 🔧 Current Patch Strategy
All Plinx customizations are stored as 4 atomic patches in `vendor/patches/strimr/`:
1. **001-engine-clip-support.patch** — Plex clip type support
2. **002-ui-landscape-layout.patch** — 16:9 landscape rendering
3. **003-logging-and-filtering.patch** — OSLog hooks
4. **004-localization-baseline.patch** — Strings & branding

The `./scripts/apply_vendor_patches.sh` script automatically applies them in order.

---

**For questions or issues, see [development/UPSTREAM_SYNC.md](./UPSTREAM_SYNC.md) and [development/STRIMR_WORKFLOWS.md](./STRIMR_WORKFLOWS.md).**
