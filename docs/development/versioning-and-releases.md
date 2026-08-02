# Versioning and releases

Plinx uses calendar versioning for user-visible releases:

```text
YYYY.MM.PP
```

`YYYY` is the release year, `MM` is the zero-padded release month, and `PP`
is the zero-padded release or hotfix sequence within that month. For example,
the current release is `2026.08.00`; a second August hotfix would be
`2026.08.01`, and the first September release would be `2026.09.00`.

## Source of truth

The Plinx marketing version is `MARKETING_VERSION` in
`PlinxApp/project.yml`. Keep it as three numeric components and use the exact
same value in the App Store submission, release notes, and Git tag:

```text
MARKETING_VERSION: 2026.08.00
Git tag: v2026.08.00
```

`CURRENT_PROJECT_VERSION` is a separate App Store build number. It is not part
of the calendar version and should remain an increasing numeric value. The
release archive script normally supplies a UTC timestamp; use `--build-number`
when a reproducible build number is required.

Strimr is a paired source dependency, not the Plinx product release. Its own
marketing version remains managed by the Strimr repository. Plinx releases
record the exact Strimr commit and branch in
`config/release-dependencies.env` instead of deriving a version from Strimr.

## Promotion sequence

Every release follows this order:

1. Finish and commit the Strimr `dev-plinx` work as focused commits. Keep the
   sibling checkout and any linked worktrees clean before publishing.
2. Push `dev-plinx` and promote it into Strimr `plinx-patches` with a
   fast-forward-only PR/update. The two Plinx patch branches should remain on
   one linear history; do not replay commits or create a merge commit. Keep
   Strimr `main` synchronized with upstream; it is not the Plinx release
   branch.
3. Fetch Strimr `plinx-patches`, set `STRIMR_BRANCH=plinx-patches`, and record
   the exact merged SHA in Plinx `config/release-dependencies.env`.
4. Run `./scripts/verify_strimr_integration_contract.sh --full`, the focused
   seam tests, package tests, documentation checks, and the release build
   gates from `docs/release/app-store.md`.
5. Push Plinx `dev` and merge its PR into Plinx `main` without changing the
   recorded dependency pin.
6. Create the annotated tag `vYYYY.MM.PP` on the merged Plinx `main` commit,
   then create the GitHub release from that tag with the user-visible summary,
   validation results, and exact paired dependency revisions.

Do not tag a dirty checkout, a development branch, or a Plinx commit whose
Strimr pin is not present on the configured paired branch. Rollback restores
the Plinx tag and exact Strimr pin together.

## Next release number

Use `PP=00` for the first planned release in a calendar month. Increment only
the patch component for follow-up fixes in that month. A release that changes
month resets the patch component to `00`; a release that changes year resets
both month and patch to the new calendar period. Update this guide's examples
only when the policy changes, not for each release.
