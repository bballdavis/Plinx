# Source Tree

## Top-Level Directory Status

| Path | Category | Guidance |
|---|---|---|
| `PlinxApp/` | Canonical app source | Main app target, resources, app unit tests, UI tests |
| `Packages/` | Canonical package source | Plinx-owned packages plus the Strimr wrapper/migration package |
| `scripts/` | Canonical tooling | Build, test, simulator, validation, and CI-support scripts |
| `.github/workflows/` | Canonical automation | CI policy and build/test orchestration |
| `docs/` | Canonical documentation | Source of truth for user and engineering Markdown content |
| `website/` | Documentation presentation | Docusaurus renderer, theme, navigation, and build-only dependency status |
| `assets/branding/` | Canonical reference assets | Marketing/reference logos and app-store artwork |
| `screenshots/` | Reference material | Product screenshots for docs and release assets |
| `README.md`, `PRIVACY_POLICY.md`, `LICENSE`, `AGENTS.md` | Canonical root docs | Minimal root-level documentation set |
| `.vscode/`, `test_creds.yaml`, `DerivedData/`, `.build/`, `build/`, generated `Plinx.xcodeproj/` | Local/generated artifacts | Never the source of truth |

## Ownership Guidance

### `PlinxApp/`

Use this for:

- app entry points and composition root
- app-facing views and navigation
- adapters between Plinx and Strimr
- decorators that wrap upstream behavior
- app resources and localized strings
- app-specific unit/UI tests

Do not treat `PlinxApp/build/` or the generated `Plinx.xcodeproj/` as canonical.

### `Packages/`

Use:

- `Packages/PlinxCore/` for safety/domain logic
- `Packages/PlinxUI/` for shared UI/theme components
- `Packages/PlinxTestSupport/` for reusable test helpers
- `Packages/StrimrEngine/` only as a wrapper/migration aid, not the active runtime engine

Ignore local package artifacts such as `.build/`, `build/`, and `.swiftpm/`.

### `assets/branding/`

Treat as the source for reference brand artwork used in docs, store material, and asset regeneration flows. For in-app branding behavior, also consult `PlinxApp/Resources/Assets.xcassets` and `docs/product/branding.md`.

### `screenshots/`

Reference material only. These are useful for docs and store assets but should not become behavioral specifications when code, tests, or current assets disagree.

### `scripts/`

Canonical for developer workflows. If a command is expected to be repeated, documented, or used in CI, prefer putting it behind a script here instead of burying it in ad hoc notes.

### `.github/workflows/`

Canonical for CI and policy enforcement. If the workflow changes, update `docs/development/ci.md` in the same PR.

### `website/`

The Docusaurus site renders `docs/` directly and deploys through GitHub Pages.
Keep product and engineering prose in `docs/`; use `website/` only for site
configuration, reusable presentation components, navigation, theme styling,
and build-time data loaders. It must not add analytics, remote search, or
third-party tracking.

### Root Docs

Keep root docs intentionally small:

- `README.md` for product and contributor orientation
- `PRIVACY_POLICY.md` for user/legal privacy disclosure
- `LICENSE` for license terms
- `AGENTS.md` for operational repository guidance

## Generated And Local Artifacts

The following must never become the source of truth:

- `PlinxApp/Plinx.xcodeproj/`
- `PlinxApp/build/`
- `Packages/*/.build/`
- `Packages/*/build/`
- `Packages/*/.swiftpm/`
- `DerivedData/`
- local `test_creds.yaml`
- simulator result bundles under `/tmp`
