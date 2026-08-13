# Architecture Overview

## Release Safety Boundaries

`ParentalAccessCoordinator` is the single authorization state for settings and other parent-only surfaces. Content flows through Plinx decorators for display and through `SafePlaybackAuthorizing` again immediately before queue launch. Playlists are reduced to authorized entries, and offline items require both current content-policy approval and a matching server/profile ownership record.

The 2026.08 App Store release ships iOS, iPadOS, and tvOS product routes.
Downloads remain limited to iOS and iPadOS. Seerr discovery/request navigation
is disabled until it can use the same authorization boundaries.

## Product Model

Plinx is a kid-safe product layer built on top of a sibling Strimr checkout. Plinx owns the product shell, branding, safety rules, parental controls, and app-specific adapters. Strimr remains the underlying media engine and Plex foundation.

Core constraints:

- Kid safety is the top-level product requirement.
- Zero collection is the privacy baseline.
- Prefer Plinx-owned adapters, decorators, and views before patching Strimr.
- Avoid copying upstream logic into Plinx-owned folders when a thin integration layer will do.

## Runtime Shape

The live iOS app does not consume Strimr as a clean public package today.

The app target defined in `PlinxApp/project.yml` compiles together:

- Plinx-owned code from `PlinxApp/App`, `Views`, `ViewModels`, `Adapters`, and `Decorators`
- sibling Strimr source from `../strimr/Shared`
- sibling Strimr iOS feature source from `../strimr/Strimr-iOS/Features`
- `Packages/PlinxCore`
- `Packages/PlinxUI`
- AetherEngine, pinned to an exact source revision

This same-module compilation model exists because parts of Strimr still depend on Swift `internal` access. AetherEngine replaces the previous MPVKit integration and is consumed only by the app target.

## Module Ownership

### `PlinxApp/`

Owns the application shell and composition root:

- app lifecycle and dependency wiring
- Plinx screens and navigation shells
- adapters that replace unsafe or incompatible Strimr implementations
- decorators that wrap upstream models/view models with Plinx behavior
- app-specific resources, unit tests, and UI tests

### `Packages/PlinxCore/`

Owns Plinx domain logic:

- safety and rating filtering
- parental gate helpers
- playback policy owned by Plinx
- public bridge models that do not depend on Strimr internals
- app-domain utilities like haptics

### `Packages/PlinxUI/`

Owns the Plinx design system:

- shared theme primitives
- reusable kid-facing components
- loading, lock, and interaction affordances
- presentation-layer abstractions that do not import Strimr

### `../strimr`

This sibling checkout is the active Strimr codebase feeding the app build. It owns generic Plex networking, playback, downloads, repositories, shared models, and other engine concerns that are not Plinx-specific.

## Practical Editing Rules

1. Plinx branding, safety, parental controls, layout, tone, and product behavior belong in Plinx-owned layers.
2. Generic playback, download, repository, or model fixes belong in the Strimr fork.
3. If Plinx needs to override a narrow upstream behavior, prefer an adapter or decorator before editing Strimr.
4. If Strimr must change, keep the patch minimal and suitable for an upstream PR where possible.
