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

## Doc Routing

- Architecture and runtime shape: `docs/architecture/`
- Branding and visual behavior: `docs/product/branding.md`
- Privacy, safety, secrets, and logging: `docs/security/privacy-and-safety.md`
- Setup, testing, branch pairing, and CI: `docs/development/`
- Release metadata: `docs/release/app-store.md`

## Update Rule

Any PR that changes app structure, branding, safety/privacy behavior, scripts, CI, or test strategy must update this file and/or the relevant file under `docs/` in the same PR.

## Instruction File Policy

- This file is the only committed direct reference to using an agent in this repository.
- Do not add duplicate instruction files such as `.github/copilot-instructions.md` or similar alternates.
