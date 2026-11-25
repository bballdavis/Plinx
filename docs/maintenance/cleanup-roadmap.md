# Cleanup Roadmap

This backlog is intentionally separate from the current documentation reorg so runtime code stays stable while repo structure gets cleaner.

## Priority 1

- [x] Consolidate generated-artifact hygiene across `PlinxApp/build/`, `Packages/*/.build/`, `Packages/*/build/`, and local cache cleanup behind the shared build environment and `scripts/clean.sh`.
- [x] Fold the redundant `PlinxApp/README.md` note into canonical documentation.
- [x] Remove duplicated package-level test fixtures in favor of the app-owned fixtures that execute them.

## Priority 2

- Rationalize script wrappers versus implementation scripts so the public entrypoints are obvious and duplicated wrapper layers stay minimal.
- [x] Remove stale references to the nonexistent `Packages/StrimrEngine`. Since the absorption the Strimr code lives in `PlinxApp/Core` and `PlinxApp/Platform`.
- Audit root-level docs periodically so new operational notes do not bypass `docs/`.

## Priority 3

- Evaluate low-risk directory consolidations inside `PlinxApp/` only when they do not cause broad churn in runtime code references.
- Revisit the current split between app unit tests, live parity tests, and shared test support for any naming or placement cleanup opportunities.
- Revisit splitting `PlinxApp/Core` into a local package once upstream ports slow down; see "Later: module boundaries" in the [hard-fork plan](strimr-hard-fork-plan.md).

## Out Of Scope For This Pass

- renaming runtime modules
