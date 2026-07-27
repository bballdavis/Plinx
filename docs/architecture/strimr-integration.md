# Strimr Integration

## Expected Local Layout

Sibling checkouts should look like:

```text
Repos/
  Plinx/
  strimr/
```

Plinx runtime builds currently expect the Strimr checkout at `../strimr` relative to the repo root and `../../strimr` relative to `PlinxApp/project.yml`.
AetherEngine is resolved by Swift Package Manager at the exact revision pinned
in `project.yml`; it is no longer a sibling checkout.

## Branch Pairing

Stable branch pairing:

- Plinx `main` <-> Strimr `plinx-patches`
- Plinx `dev` <-> Strimr `dev-plinx`

Plinx `dev` currently pins Strimr `dev-plinx` at
`554256d78bd7e338d57567aa54b60019f5d89a6d`, based on upstream `main` at
`e0a8cbc`. CI and release builds use that exact commit rather than resolving a
moving branch head.

See `docs/development/branch-pairing.md` for commands and day-to-day verification steps.

## When To Change Plinx Instead Of Strimr

Prefer Plinx-owned layers when the change is:

- product-specific
- kid-safety specific
- branding or copy specific
- a layout or UX override
- a narrow adaptation around upstream behavior

Preferred order:

1. Plinx view or view model
2. Plinx adapter or decorator
3. Plinx package API
4. minimal Strimr patch only if the above are not sufficient

## When Strimr Should Change

Patch the Strimr fork when the fix is generic and would still matter without the Plinx product, especially for:

- Plex networking or repositories
- playback engine behavior
- download engine behavior
- shared models and stores
- engine-level concurrency or lifecycle bugs

The migration keeps Plinx-only presentation, maximum-volume policy, and
fail-closed playback authorization out of generic upstream PRs. Reusable
filtering injection points, strict Plex boolean decoding, clip support, and the
SharePlay presentation policy are maintained as independently reviewable
upstream candidates.

## Upstream PR Candidate Criteria

Flag a Strimr-side change as an upstream candidate when it is:

- generic rather than Plinx-branded
- not dependent on Plinx-only product rules
- small enough to explain and review independently
- backed by a focused test or reproducible failure case

When a Plinx need forces a Strimr patch, document:

1. why the patch could not live in Plinx-owned layers
2. whether it is temporary or expected to remain upstreamable
3. which branch pairing or dependency assumption it relies on

## Current Release Patch

The pinned `dev-plinx` revision contains the Strimr-side injection points that
cannot be supplied by a Plinx decorator:

- tvOS playback-gain propagation and MPV lifecycle reapplication;
- an optional authorization callback before autoplay or next-queue playback on iOS and tvOS.
- default-allow playlist and media-detail cache authorization hooks required because those upstream views load their own models.

Plinx supplies the actual content decision in `StrimrAdapter`; Strimr remains unaware of Plinx policy or product copy.
