# Upstream Synchronization Strategy

Plinx is built upon the **Strimr** media engine. We maintain a philosophy of staying as close to upstream as possible to benefit from their core improvements while contributing back generic enhancements.

## The Vendor Strategy
- **Upstream:** `https://github.com/wunax/strimr`
- **Location:** `vendor/strimr` (git submodule; canonical lowercase path)

Branch-first source of truth:
- **Canonical state:** commits on local `plinx-strimr-patching` branch in `vendor/strimr`
- **Replay artifacts:** `vendor/Patches/strimr/*.patch` (numbered patches for deterministic re-apply)
- **Machine-readable index:** `vendor/Patches/strimr/manifest.yaml`

We treat `vendor/strimr` as a managed dependency. We do not modify files inside this folder directly unless working on the local patch branch and capturing those changes as patch artifacts + manifest updates.

## Contribution Workflow

Our goal is to be a "good citizen" of the Strimr ecosystem. **Whenever we develop a new feature, engine improvement, or bug fix that is not strictly unique to the Plinx kid-friendly brand, our primary intention is to upstream it.**

1. **Isolation:** Keep engine-level changes (new features, player improvements, bug fixes) in separate commits or branches.
2. **Generic Implementation:** Ensure changes are built to be generally useful to the Strimr community and don't rely on `PlinxCore` or Plinx-specific UI assets.
3. **Upstream First:** Prioritize pushing features back to `wunax/strimr`. Once merged, we update our local submodule to utilize the official implementation.

## Maintenance Procedures

### Updating the Submodule
To pull the latest changes from Strimr:
1. Update the submodule:
   ```bash
   git submodule update --remote --merge vendor/strimr
   ```

2. Re-apply Plinx-specific patches:
   We treat vendor modifications like **migrations**. If Strimr's core changes, we re-run our patch artifacts after validation:
   ```bash
   ./scripts/validate_vendor_patches.sh
   ./scripts/apply_vendor_patches.sh
   ```

3. If a patch fails (due to upstream structural changes):
   - Resolve conflicts in `vendor/strimr`.
   - Re-generate the specific atomic patch in `vendor/Patches/strimr/`.
   - Update `vendor/Patches/strimr/manifest.yaml` entry metadata + file lists.
   - Re-run strict governance validation:
     ```bash
     ./scripts/validate_vendor_patches.sh --strict-clean --compare-working-tree
     ```
   - Commit the new patch to the Plinx repository.

4. Commit the new submodule pointer:
   ```bash
   git add vendor/strimr vendor/Patches/strimr
   git commit -m "chore: sync Strimr upstream and re-apply patches"
   ```

### Patch Organization
Plinx maintaining the following patches for Strimr:
- `001-engine-clip-support`: Adds Plex `clip` ("Other Videos") item type support.
- `002-ui-landscape-layout`: Implements 16:9 landscape card support for clip libraries.
- `003-logging-and-filtering`: Provides OSLog hooks and promoted hub classification.
- `004-localization-baseline`: Adds Plinx localization strings to the vendor layer.
- `005-branding-assets`: Applies Plinx color asset overrides in vendor catalogs.
- `006-library-player-session-sync`: Captures current library/session/player flow updates not covered by earlier baseline patches.

Governance checks:

```bash
./scripts/validate_vendor_patches.sh
./scripts/validate_vendor_patches.sh --strict-clean --compare-working-tree
```

### Build Guardrails
Currently, our CI focus is on the `Plinx-iOS` target. While Strimr supports tvOS, we prioritize iOS stability and Liquid Glass performance first. tvOS support is maintained as "experimental/legacy" inside the vendor folder for future exploration.

---

*Note: For proprietary or brand-sensitive "Local Only" instructions, refer to `.local_dev/` (not tracked in public git).*
