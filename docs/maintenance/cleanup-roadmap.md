# Cleanup Roadmap

This backlog is intentionally separate from the current documentation reorg so runtime code stays stable while repo structure gets cleaner.

## Priority 1

- [x] Consolidate generated-artifact hygiene across `PlinxApp/build/`, `Packages/*/.build/`, `Packages/*/build/`, and local cache cleanup behind the shared build environment and `scripts/clean.sh`.
- [x] Fold the redundant `PlinxApp/README.md` note into canonical documentation.
- [x] Remove duplicated package-level test fixtures in favor of the app-owned fixtures that execute them.

## Priority 2

- Rationalize script wrappers versus implementation scripts so the public entrypoints are obvious and duplicated wrapper layers stay minimal.
- [x] Remove stale references to the nonexistent `Packages/StrimrEngine`; the paired checkout is the only Strimr source of truth.
- Audit root-level docs periodically so new operational notes do not bypass `docs/`.

## Priority 3

- Evaluate low-risk directory consolidations inside `PlinxApp/` only when they do not cause broad churn in runtime code references.
- Revisit the current split between app unit tests, live parity tests, and shared test support for any naming or placement cleanup opportunities.
- Reassess whether future Strimr seam improvements could reduce same-module compilation pressure and simplify the runtime build graph.

## Out Of Scope For This Pass

- sweeping Strimr integration rewrites
- renaming runtime modules
