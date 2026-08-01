# Branch Pairing

## Canonical Pairing

- Plinx `main` pairs with Strimr `main`
- Plinx `dev` pairs with Strimr `dev-plinx`

The machine-readable source of truth is
`config/release-dependencies.env`. It records the exact release commit, the
paired branch, the upstream base, and the source seams that Plinx compiles.

The current branch, exact Strimr commit, and upstream base are displayed from
the canonical configuration on the [current dependency status](../maintenance/current-dependencies.mdx)
page. Do not duplicate those moving values in this guide.

## Expected Local Layout

```text
Repos/
  Plinx/
  strimr/
```

Plinx runtime builds expect the sibling checkout at `../strimr`.

## Verification Commands

```bash
# Fast source and XcodeGen contract checks
./scripts/verify_strimr_integration_contract.sh --quick

# Required before a paired build, CI-equivalent verification, or release work
./scripts/verify_strimr_integration_contract.sh --full
```

`--quick` verifies the configured source roots and the narrow Strimr symbols
that Plinx requires. It does not modify either checkout. `--full` adds the
clean-tree requirement, checks the configured branch and exact pin, verifies
that the configured upstream base is an ancestor, and rejects merge commits in
the downstream patch stack.

## Before Starting Work

1. Decide whether the change belongs in Plinx or Strimr before editing.
2. Verify the full contract before building the paired app.
3. Keep candidate engine changes on a Strimr branch; do not add product policy
   to the generic engine.
4. For either branch, verify Strimr resolves to the commit recorded in
   `config/release-dependencies.env` before testing Plinx.

## Promoting Dev To Main

Use the [versioning and release guide](versioning-and-releases.md) for the
complete calendar-release sequence. The paired promotion order is deliberate:

1. Commit and push the clean Strimr `dev-plinx` stack, then merge its PR into
   Strimr `main` without introducing a merge commit.
2. Fetch the resulting Strimr `main` commit and update Plinx's exact
   `STRIMR_COMMIT` and `STRIMR_BRANCH=main` values.
3. Run the full pairing contract with both repositories clean, then merge the
   Plinx `dev` PR into Plinx `main`.
4. Tag the merged Plinx commit with the calendar release tag and create the
   GitHub release only after the paired source revisions are recorded.

## Updating A Strimr Candidate

Never rebase the published `dev-plinx` branch in place while Plinx points to
it. Treat it as the currently promoted integration release.

1. Fetch `upstream/main` and create a `candidate/plinx-<upstream-short-sha>` branch from
   the new upstream commit. Reapply the downstream commits there as a linear
   patch train; do not merge upstream into the candidate.
2. Compare the old and candidate stacks with `git range-diff`, review every
   conflict resolution, and run Strimr's own builds and tests.
3. In a paired Plinx candidate, update `STRIMR_COMMIT` to the candidate's exact
   SHA and `STRIMR_UPSTREAM_BASE` to the fetched upstream SHA. Run the full
   contract and all iOS/tvOS seam tests and builds.
4. After review and a testing soak, archive the old `dev-plinx` tip with an
   annotated tag such as `plinx/archive-YYYY-MM-DD`. Promote the candidate to
   `dev-plinx` with an explicit `--force-with-lease=<old-tip>` only when its
   history was rebuilt; a fast-forward is preferred whenever possible.
5. Push Strimr first, verify the remote commit, then merge/push the paired Plinx
   pin. Rollback means restoring both the archived Strimr tip and the prior
   Plinx pin together.
6. In Plinx, update `STRIMR_COMMIT` and, when upstream moved,
   `STRIMR_UPSTREAM_BASE` in `config/release-dependencies.env`. Update the
   seam records only when a deliberate integration surface changes.
7. Run `./scripts/verify_strimr_integration_contract.sh --full`, the focused
   seam tests, and the relevant app build. Update this document and
   `docs/architecture/strimr-integration.md` when the integration shape
   changes.

The exact pin remains authoritative: the expected branch name is an audit
constraint, never a request to resolve or build from a moving branch head.

## Recording Every Strimr Edit

Any change in the sibling Strimr repository must leave a durable migration
record in Plinx in the same workstream. Before considering the change complete:

1. Record the capability and disposition in
   `docs/maintenance/strimr-upstream-audit-2026-07-25.md`.
2. Add or update a focused file in
   `docs/maintenance/strimr-contributions/` when the change is generic,
   upstreamable, or must be replayed on the next Strimr baseline.
3. Update `STRIMR_REQUIRED_SEAMS` when Plinx compilation or behavior depends on
   a stable source token in the sibling checkout.
4. Commit and push Strimr first, then update Plinx's exact `STRIMR_COMMIT`.
   A dirty sibling checkout is useful for development but is not a valid
   release pairing.
5. Run the full integration contract and the validation named by the focused
   contribution plan.

During the next Strimr upgrade, review this inventory before resolving source
conflicts. Mark each downstream patch as adopted upstream, dropped as obsolete,
kept in a Plinx-owned layer, or replayed as a minimal generic seam.

## Rule Of Thumb

If the change is product-specific, work in Plinx. If the change is engine-specific or generally useful, work in Strimr.
