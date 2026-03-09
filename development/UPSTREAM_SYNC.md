# Upstream Synchronization Strategy

Plinx is built upon the **Strimr** media engine. We maintain a philosophy of staying as close to upstream as possible to benefit from their core improvements while contributing back generic enhancements.

## The Vendor Strategy
- **Fork:** `https://github.com/bballdavis/strimr` (`origin`)
- **Upstream:** `https://github.com/wunax/strimr` (`upstream`)
- **Location:** sibling checkout at `../strimr` (canonical local working tree)

Git-history-as-patch-series:
- **Canonical state:** commits on `plinx-patches` branch in the fork (`origin/plinx-patches`)
- **Upstream tracking:** `upstream/main` — fetch from here to sync, never push
- **Fork's `main`** stays in sync with `upstream/main` for clean PR comparisons

We treat the sibling `../strimr` checkout as the managed dependency. All Plinx-specific edits live as commits on `plinx-patches`. Generic improvements are PRed from a feature branch to `wunax/strimr`, then rebased into `plinx-patches` after merge.

## Contribution Workflow

Our goal is to be a "good citizen" of the Strimr ecosystem. **Whenever we develop a new feature, engine improvement, or bug fix that is not strictly unique to the Plinx kid-friendly brand, our primary intention is to upstream it.**

1. **Isolation:** Keep engine-level changes (new features, player improvements, bug fixes) in separate commits or branches.
2. **Generic Implementation:** Ensure changes are built to be generally useful to the Strimr community and don't rely on `PlinxCore` or Plinx-specific UI assets.
3. **Upstream First:** Prioritize pushing features back to `wunax/strimr`. Once merged, we update the sibling checkout to utilize the official implementation.

## Maintenance Procedures

### Syncing with Upstream

```bash
cd ../strimr
git fetch upstream
git rebase upstream/main      # rebases plinx-patches on top of new upstream commits
# resolve any conflicts, then:
git push origin plinx-patches --force-with-lease

# Keep fork's main in sync:
git checkout main
git merge upstream/main --ff-only
git push origin main
git checkout plinx-patches
```

### Patch Organization

Plinx patches live as commits on `plinx-patches`. View the full set:

```bash
cd ../strimr
git log --oneline upstream/main..HEAD
```

Areas currently covered:
- Engine `clip` item type support (Plex "Other Videos")
- 16:9 landscape card layout for clip libraries
- OSLog hooks and hub classification filtering
- Plinx localization strings in the Strimr layer
- Color asset overrides in Strimr catalogs
- Library/session/player flow extensions
- Kids UX improvements (icon tab picker, hide browse controls, playlist filtering)

### Build Guardrails
Currently, our CI focus is on the `Plinx-iOS` target. While Strimr supports tvOS, we prioritize iOS stability and Liquid Glass performance first. tvOS support is maintained as "experimental/legacy" inside the sibling Strimr checkout for future exploration.

---

*Note: For proprietary or brand-sensitive "Local Only" instructions, refer to `.local_dev/` (not tracked in public git).*
