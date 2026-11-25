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

The code Plinx absorbed from Strimr is part of the Plinx release; it has no
separate version or pin. A Plinx release is identified by its Plinx commit and
tag alone. The Swift package pins in `PlinxApp/project.yml` are part of that
commit.

## Promotion sequence

Every release follows this order:

1. Finish the release work on Plinx `dev` as focused commits, with a clean
   checkout.
2. Run the package tests, both app builds and their unit tests (including
   `SafeMediaServicesTests`), the documentation checks, and the release build
   gates from `docs/release/app-store.md`.
3. Push Plinx `dev` and merge its PR into Plinx `main`.
4. Create the annotated tag `vYYYY.MM.PP` on the merged Plinx `main` commit.
5. Build the corresponding-source bundle from that tag with
   `scripts/build_compliance_bundle.sh`; see
   [open-source compliance](../release/open-source-compliance.md).
6. Create the GitHub release from the tag with the user-visible summary,
   validation results, and the bundle's `SOURCE-MANIFEST.txt` (Plinx commit
   and Swift package pins).

Do not tag a dirty checkout or a development branch. Rollback means
re-releasing an earlier tag.

Releases made before the Strimr absorption (2026-11-23) also depend on the
Strimr commit recorded in that tag's `config/release-dependencies.env`. Rebuild
or roll back to one of those releases only with that exact Strimr commit from
the `bballdavis/strimr` repository.

## Next release number

Use `PP=00` for the first planned release in a calendar month. Increment only
the patch component for follow-up fixes in that month. A release that changes
month resets the patch component to `00`; a release that changes year resets
both month and patch to the new calendar period. Update this guide's examples
only when the policy changes, not for each release.
