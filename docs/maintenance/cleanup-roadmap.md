# Cleanup Roadmap

This backlog is intentionally separate from the current documentation reorg so runtime code stays stable while repo structure gets cleaner.

## Priority 1

- [x] Consolidate generated-artifact hygiene across `PlinxApp/build/`, `Packages/*/.build/`, `Packages/*/build/`, and local cache cleanup behind the shared build environment and `scripts/clean.sh`.
- Review whether `PlinxApp/README.md` should remain as a short local note or be folded fully into `docs/development/setup.md`.
- Consolidate any duplicated test-helper or fixture locations that are causing ambiguity between app tests and package tests.

## Priority 2

- Rationalize script wrappers versus implementation scripts so the public entrypoints are obvious and duplicated wrapper layers stay minimal.
- Clarify whether `Packages/StrimrEngine` should keep its current name or gain stronger in-repo documentation/comments around its wrapper-only role.
- Audit root-level docs periodically so new operational notes do not bypass `docs/`.

## Priority 3

- Evaluate low-risk directory consolidations inside `PlinxApp/` only when they do not cause broad churn in runtime code references.
- Revisit the current split between app unit tests, live parity tests, and shared test support for any naming or placement cleanup opportunities.
- Reassess whether future Strimr seam improvements could reduce same-module compilation pressure and simplify the runtime build graph.

## Out Of Scope For This Pass

- feature-slice reorganization across `PlinxApp/Views`, `ViewModels`, `Adapters`, or `Decorators`
- sweeping Strimr integration rewrites
- renaming runtime modules or changing public Swift interfaces
