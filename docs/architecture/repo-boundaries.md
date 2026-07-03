# Repo Boundaries

## Goal

Keep Plinx code in Plinx and Strimr engine code in Strimr. Do not let wrappers, copied files, or convenience shims become a shadow third codebase.

## What Belongs In Plinx

- kid-safe UX and product rules
- parental gate flows and settings protection
- Plinx branding, assets, copy, and loading states
- Plinx-specific navigation and screen composition
- adapters and decorators that reshape upstream behavior for the Plinx product
- `Packages/PlinxCore` and `Packages/PlinxUI`
- build, release, validation, and local development scripts

## What Belongs In Strimr

- generic Plex integration logic
- shared models and repositories
- playback engine behavior
- download engine behavior
- session/store infrastructure
- fixes that still make sense without the Plinx product

## What `Packages/StrimrEngine` Is Allowed To Be

`Packages/StrimrEngine` should remain a thin local wrapper around the sibling Strimr checkout.

Allowed:

- package manifests
- exports and shims needed for validation or future migration
- structure that mirrors sibling Strimr source layout

Not allowed:

- accumulating runtime feature work that actually belongs in the sibling Strimr checkout
- becoming the assumed home for engine behavior just because it lives in the Plinx repo

## Decision Checklist

Ask these in order:

1. Would this change exist if Plinx did not exist?
2. Is the behavior generic enough that Strimr should own it?
3. Can Plinx solve this with an adapter, decorator, or app-level wrapper?
4. If Strimr must change, can the patch stay minimal and upstreamable?

If the answer to 1 or 2 is yes, the work probably belongs in the Strimr fork. If the answer to 3 is yes, keep it in Plinx.

## Current Runtime Reality

Plinx still compiles parts of the sibling `../strimr` checkout directly into the app target.

That means:

- the sibling Strimr repo is part of the effective runtime source tree
- `Packages/StrimrEngine` is not the authoritative runtime implementation
- editing only the wrapper package can create false confidence

## Working Policy

Use this policy until the architecture is simplified further:

1. Treat `../strimr` as the canonical home for Strimr-owned logic.
2. Treat `Packages/StrimrEngine` as a wrapper, validation aid, and migration tool.
3. Keep Plinx-specific changes out of the Strimr repo unless they are the smallest safe patch needed to unblock Plinx.
4. When a Strimr-side change is necessary for Plinx, document why it could not live in Plinx-owned layers.
