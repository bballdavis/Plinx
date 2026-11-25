# Plinx Repository Guidance

## Core Principles

- Kid safety comes first.
- Zero collection is the privacy baseline.
- No external links in kid-facing UI; legal and source links belong behind parental gate or settings surfaces.
- Preserve required upstream license notices and compliance obligations.

## Change Routing

- Plinx is one codebase. `PlinxApp/Core` and `PlinxApp/Platform` hold the code absorbed from Strimr and are Plinx code: edit them in place, coherently, like any other Plinx folder. There is no sibling checkout, pin, or seam contract.
- Put a change where its concept lives: shared session, provider, model, and player behavior in `PlinxApp/Core`; platform screens in `PlinxApp/Platform/<platform>`; Plinx presentation in `PlinxApp/Views`, `ViewModels`, and `Adapters`; app wiring in `PlinxApp/App`; policy and design primitives in `Packages/PlinxCore` and `Packages/PlinxUI`.
- Keep one implementation per concept. Do not override a type by excluding its file and declaring a same-named replacement; change or delete the original.
- Content safety is enforced at the boundary in `PlinxApp/Core/Safety` (`ContentSafetyGate`, `SafeMediaServices`). Every content source goes through `MediaServices` or is listed with its own fail-closed control in `docs/architecture/strimr-integration.md`. New provider protocol requirements must be classified in `SafeMediaServices.reviewedRequirements` and covered by `SafeMediaServicesTests`.
- Keep persisted identifiers that came from Strimr (for example the Keychain key `strimr.plex.authToken`) unless a migration preserves existing families' sign-in and data.
- Upstream Strimr is a source of ideas and fixes, not a dependency. Port upstream changes by hand following `docs/maintenance/upstream-strimr.md`, cite the upstream commit, record the review there, and judge every change against the core principles above. Never re-add a sibling checkout, pin, or automated upstream sync.
- `docs/maintenance/strimr-contributions/` and `docs/maintenance/strimr-upstream-audit-2026-07-25.md` are historical records of the paired era; do not extend them for new work.

## Doc Routing

- User, parent, privacy, and support guidance: `docs/user/`
- Architecture and runtime shape: `docs/architecture/`
- Branding and visual behavior: `docs/product/branding.md`
- Privacy, safety, secrets, and logging: `docs/security/privacy-and-safety.md`
- Codebase layers and the safety boundary: `docs/architecture/strimr-integration.md`
- Upstream Strimr provenance and porting: `docs/maintenance/upstream-strimr.md`
- Setup, testing, releases, and CI: `docs/development/`
- Corresponding source and license obligations: `docs/release/open-source-compliance.md`
- Release metadata: `docs/release/app-store.md`
- Documentation presentation and navigation: `website/`; it renders `docs/` and is not a second documentation source.

## Update Rule

Any PR that changes app structure, user-visible behavior, branding, safety/privacy behavior, scripts, CI, test strategy, or dependencies must update this file and/or the relevant file under `docs/` in the same PR. Changes to `website/` must pass its documentation tests, type-check, and production build.

## Documentation And Dependency Rules

- Keep prose in `docs/`; do not copy it into `website/` pages or components.
- Preserve the zero-collection baseline for the public documentation site: no analytics, remote search, trackers, or third-party embeds without an explicit privacy decision and documentation update.
- The absorbed Strimr base is owned by `config/release-dependencies.env` (`STRIMR_FORK_BASE`). The exact Swift package pins (AetherEngine, GRDB, SwiftAssRenderer) and the configured Xcode version are owned by `PlinxApp/project.yml`. Render them through the documentation dependency-status loader; do not hard-code current package revisions in narrative docs.
- Pin every remote Swift package to an exact `revision` or `exactVersion`, and add its license to the in-app license list before it ships.
- The Plinx repository is the complete corresponding source for every build made from it. Keep Strimr's attribution and license notices. Keep the `bballdavis/strimr` fork read-only and available: its pinned commits are the corresponding source for releases made before the absorption.

## Instruction File Policy

- This file is the only committed direct reference to using an agent in this repository.
- Do not add duplicate instruction files such as `.github/copilot-instructions.md` or similar alternates.
