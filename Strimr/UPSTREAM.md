# Strimr In Plinx

This directory is Plinx's hard fork of [Strimr](https://github.com/wunax/strimr)
(GPL-3.0, see `LICENSE`). It is Plinx source, so edit it in place. There is no
sibling checkout, pin, or seam contract.

| Field | Value |
|---|---|
| Fork base | `0235d271d6b444c45df3c071f9bd4482e2b0f6f1` (upstream `main`, 2026-11-21) |
| Imported | 2026-11-23 |
| Last upstream feature review | 2026-11-23 (see `docs/maintenance/strimr-contributions/15-upstream-main-migration-plan.md`) |

`UPSTREAM-README.md` is upstream's README, kept for attribution.

## Porting upstream changes

The `upstream` remote points at `wunax/strimr`.

```bash
git fetch upstream
git log --oneline <last-reviewed>..upstream/main
git cherry-pick -x -X subtree=Strimr <commit>
```

Record each review date above. Follow `docs/maintenance/strimr-hard-fork-plan.md`
for what Plinx adopts, gates, or rejects.
