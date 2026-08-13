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
- there is no local shadow `StrimrEngine` package
- Strimr-owned changes must be made and accounted for in the paired checkout

## Working Policy

Use this policy until the architecture is simplified further:

1. Treat `../strimr` as the canonical home for Strimr-owned logic.
2. Keep Plinx-specific changes out of the Strimr repo unless they are the smallest safe patch needed to unblock Plinx.
3. When a Strimr-side change is necessary for Plinx, document why it could not live in Plinx-owned layers.
