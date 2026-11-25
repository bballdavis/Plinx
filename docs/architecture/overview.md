# Architecture Overview

## Release Safety Boundaries

`ParentalAccessCoordinator` is the single authorization state for settings and
other parent-only surfaces. Every content source a provider exposes passes one
boundary: `MediaServices.init` wraps each service in `SafeMediaServices`,
which asks `ContentSafetyGate` about every title (`PlinxApp/Core/Safety`).
Playback checks each title again in `PlinxPlaybackLauncher` and at the player's
load site. Playlists are reduced to allowed entries, and a download plays only
for the profile that owns it and only while the current policy allows it.

The 2026.08 App Store release ships iOS, iPadOS, and tvOS product routes.
Downloads remain limited to iOS and iPadOS. Seerr discovery and requests stay
off for kids until they can use the same authorization boundaries, and Live TV
is not offered.

## Product Model

Plinx is one codebase. In November 2026 it absorbed the source of Strimr, the
open-source Plex and Jellyfin client it used to build against; that code is
now Plinx code, edited in place. Plinx owns the whole app: the product shell,
branding, safety rules, parental controls, the provider layer for Plex and
Jellyfin, sessions, playback, and downloads.

Core constraints:

- Kid safety is the top-level product requirement.
- Zero collection is the privacy baseline.
- No external links in kid-facing UI.
- One implementation per concept: change or delete the original instead of
  adding a wrapper or a same-named replacement.
- Enforce content safety at the boundary, not screen by screen.

## Runtime Shape

`PlinxApp/project.yml` defines one app target per platform (`Plinx-iOS`,
`Plinx-tvOS`). Each compiles a single module from:

- the Plinx layer: `PlinxApp/App`, `Views`, `ViewModels`, and `Adapters`
- the absorbed media stack: `PlinxApp/Core` and
  `PlinxApp/Platform/<platform>`
- the local packages `Packages/PlinxCore` and `Packages/PlinxUI`
- Swift packages pinned exactly in `project.yml`: AetherEngine (playback),
  GRDB (the offline store), and SwiftAssRenderer (ASS and SSA subtitles)

AetherEngine is consumed only by the app targets. See the
[runtime build graph](runtime-build-graph.md) and the
[codebase architecture](strimr-integration.md) for the composition root,
sessions, and the safety boundary.

## Module Ownership

### `PlinxApp/App`

The composition root (`PlinxApp.swift`), lifecycle hardening,
`ParentalAccessCoordinator`, settings sanitizing, the App Review sample
library, UI-test bootstraps, and the Youtarr client.

### `PlinxApp/Views`, `ViewModels`, `Adapters`

Plinx presentation: root tabs and onboarding, profile selection, Home,
Library, Search, detail screens, player chrome and timeline, parent settings
(including sign-out), the downloads grid, playback launch, and watched state.

### `PlinxApp/Core`

The shared media stack: sessions, accounts and the server registry, the Plex
and Jellyfin providers, the content-safety boundary (`Core/Safety`), feature
view models, the player controller, models, networking, the offline store and
downloads (iOS), and the settings store.

### `PlinxApp/Platform/<platform>`

Platform screens kept from upstream: player wrappers and views, detail and
library pieces, downloads (iOS), and settings sections Plinx reuses.

### `Packages/PlinxCore/`

Plinx domain logic with no app dependencies:

- `SafetyPolicy`, `SafetyInterceptor`, and rating normalization
- parental gate helpers
- app-domain utilities like haptics

### `Packages/PlinxUI/`

The Plinx design system:

- shared theme primitives
- reusable kid-facing components
- loading, lock, and interaction affordances

## Practical Editing Rules

1. Put a change where its concept lives: shared session, provider, model, and
   player behavior in `Core`; a platform screen in `Platform/<platform>`;
   Plinx presentation in `Views`, `ViewModels`, and `Adapters`; app wiring in
   `App`; policy and design primitives in the packages.
2. Content safety belongs in `Core/Safety`. A new provider requirement needs a
   classification in `SafeMediaServices.reviewedRequirements` and coverage in
   `SafeMediaServicesTests`.
3. Keep persisted identifiers, such as the Keychain key
   `strimr.plex.authToken`, unless a migration preserves families' sign-in and
   data.
4. Port upstream Strimr changes by hand, following
   [upstream Strimr provenance](../maintenance/upstream-strimr.md).
