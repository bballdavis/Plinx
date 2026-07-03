# Plinx Engineering Docs

## Read This First

Use this directory as the canonical engineering source of truth for Plinx.

Recommended reading order for most work:

1. `docs/architecture/overview.md`
2. `docs/architecture/repo-boundaries.md`
3. `docs/development/setup.md`
4. `docs/development/testing.md`

## Find The Right Doc

| Question | Source of truth |
|---|---|
| How the app is composed at runtime | `docs/architecture/overview.md` |
| How `project.yml` builds the app and pulls in Strimr | `docs/architecture/runtime-build-graph.md` |
| Where a change belongs: Plinx vs Strimr | `docs/architecture/repo-boundaries.md` |
| Current repository layout and what is generated vs canonical | `docs/architecture/source-tree.md` |
| Sibling checkout expectations and branch pairing | `docs/architecture/strimr-integration.md` and `docs/development/branch-pairing.md` |
| Local setup and daily build commands | `docs/development/setup.md` |
| Which tests to run for a given change | `docs/development/testing.md` |
| Snapshot and UI test strategy details | `docs/development/ui-testing.md` |
| CI behavior and documentation guardrails | `docs/development/ci.md` |
| Brand assets, theme rules, and UI branding expectations | `docs/product/branding.md` |
| Privacy, safety, secrets, and release validation rules | `docs/security/privacy-and-safety.md` |
| App Store submission copy | `docs/release/app-store.md` |
| Future cleanup candidates outside this pass | `docs/maintenance/cleanup-roadmap.md` |

## Repo Map

| Path | Role | Status |
|---|---|---|
| `PlinxApp/` | Application shell, composition root, app tests, resources | Canonical |
| `Packages/PlinxCore/` | Safety, playback policy, public bridge models, app-domain utilities | Canonical |
| `Packages/PlinxUI/` | Plinx design system and reusable UI | Canonical |
| `Packages/PlinxTestSupport/` | Shared test fixtures/helpers | Canonical |
| `Packages/StrimrEngine/` | Local wrapper/migration aid around Strimr seams | Canonical, but not runtime source of truth |
| `scripts/` | Build, simulator, validation, and test commands | Canonical |
| `.github/workflows/` | CI enforcement and build automation | Canonical |
| `assets/branding/` | Marketing/reference brand assets | Canonical reference assets |
| `screenshots/` | Product screenshots for docs/store material | Reference material |
| `docs/` | Engineering documentation | Canonical |
| `PlinxApp/Plinx.xcodeproj/`, `build/`, `.build/`, `.swiftpm/`, `DerivedData/` | Generated local artifacts | Never source of truth |

## Change Matrix

| Change type | Update docs | Minimum validation |
|---|---|---|
| App structure, target composition, package boundaries | `docs/architecture/overview.md`, `docs/architecture/runtime-build-graph.md`, `docs/architecture/source-tree.md` | `swift test --package-path Packages/PlinxCore`, `swift test --package-path Packages/PlinxUI`, app unit tests |
| Plinx vs Strimr ownership change | `docs/architecture/repo-boundaries.md`, `docs/architecture/strimr-integration.md` | Tests covering the touched layer plus any affected live parity checks |
| Branding, theme, assets, or kid-facing UI chrome | `docs/product/branding.md` | Branding/unit tests, relevant snapshot tests, targeted UI tests |
| Safety, privacy, logging, secrets, or parental gate behavior | `docs/security/privacy-and-safety.md`, `docs/development/testing.md` | Safety/unit tests, targeted UI tests, release/archive validation when applicable |
| Scripts, CI, or contributor workflow | `docs/development/setup.md`, `docs/development/testing.md`, `docs/development/ci.md` | Run the modified script locally when possible; run docs guard |
| Release metadata or submission workflow | `docs/release/app-store.md`, `docs/development/ci.md` | Archive validation and any release-script checks touched by the change |

When a change does not alter the source of truth, still refresh the relevant doc in the same PR or confirm that no update was needed.
