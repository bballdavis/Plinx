# Plinx Repository Guidance

## Core Principles

- Kid safety comes first.
- Zero collection is the privacy baseline.
- No external links in kid-facing UI; legal and source links belong behind parental gate or settings surfaces.
- Preserve required upstream license notices and compliance obligations.

## Change Routing

- Prefer Plinx-owned layers first: `PlinxApp/`, `Packages/PlinxCore/`, and `Packages/PlinxUI/`.
- Treat Strimr-side edits as escalations, not defaults.
- Before editing Strimr-owned code, confirm the requirement cannot be solved in Plinx adapters, decorators, views, view models, or packages.
- If Strimr changes are unavoidable, keep the patch minimal, document why it is needed, and identify upstream PR candidates when the fix is generic.
- Every Strimr-side edit must be recorded in the same change in the Strimr
  upgrade inventory at
  `docs/maintenance/strimr-upstream-audit-2026-07-25.md`. Add or update a
  focused plan under `docs/maintenance/strimr-contributions/` when the patch is
  generic or expected to be replayed, and update `STRIMR_REQUIRED_SEAMS` when
  Plinx depends on a source-level integration token. Do not leave required
  sibling-repository work represented only by an uncommitted checkout.

## Doc Routing

- User, parent, privacy, and support guidance: `docs/user/`
- Architecture and runtime shape: `docs/architecture/`
- Branding and visual behavior: `docs/product/branding.md`
- Privacy, safety, secrets, and logging: `docs/security/privacy-and-safety.md`
- Setup, testing, branch pairing, and CI: `docs/development/`
- Release metadata: `docs/release/app-store.md`
- Documentation presentation and navigation: `website/`; it renders `docs/` and is not a second documentation source.

## Update Rule

Any PR that changes app structure, user-visible behavior, branding, safety/privacy behavior, scripts, CI, test strategy, or dependency pairing must update this file and/or the relevant file under `docs/` in the same PR. Changes to `website/` must pass its documentation tests, type-check, and production build.

## Documentation And Dependency Rules

- Keep prose in `docs/`; do not copy it into `website/` pages or components.
- Preserve the zero-collection baseline for the public documentation site: no analytics, remote search, trackers, or third-party embeds without an explicit privacy decision and documentation update.
- The exact current Strimr pin, upstream base, AetherEngine revision, and Xcode version are owned by `config/release-dependencies.env`, `PlinxApp/project.yml`, and `.xcode-version`. Render them through the documentation dependency-status loader; do not hard-code current revisions in narrative docs.
- Strimr upgrades are manual compatibility work. Never automatically advance the paired branch or pin; follow `docs/development/branch-pairing.md` and run the full integration contract before changing it.
- A Strimr migration is not complete until the upgrade inventory accounts for
  every downstream patch as adopted, dropped, kept in Plinx, or replayed; the
  paired Strimr commit is pushed; and the exact Plinx pin passes the full
  integration contract.

## Instruction File Policy

- This file is the only committed direct reference to using an agent in this repository.
- Do not add duplicate instruction files such as `.github/copilot-instructions.md` or similar alternates.
