# Repo Boundaries

## Goal

Plinx is one codebase. The code absorbed from Strimr in `PlinxApp/Core` and
`PlinxApp/Platform` is Plinx code. Keep one implementation per concept, and do
not let wrappers, copied files, or convenience shims grow a shadow layer
beside the code they wrap.

## Where A Change Belongs

| Concept | Location |
|---|---|
| Sessions, accounts, server registry, providers (Plex, Jellyfin), models, networking, player controller, offline store, downloads, settings store | `PlinxApp/Core` |
| The content-safety boundary (`ContentSafetyGate`, `SafeMediaServices`) | `PlinxApp/Core/Safety` |
| A platform screen kept from upstream | `PlinxApp/Platform/iOS` or `PlinxApp/Platform/tvOS` |
| Plinx presentation: tabs, onboarding, Home, Library, Search, detail, player chrome, settings, downloads grid | `PlinxApp/Views`, `ViewModels`, `Adapters` |
| App wiring, lifecycle, parental access, the sample library, Youtarr client | `PlinxApp/App` |
| Safety policy, rating normalization, parental gate logic | `Packages/PlinxCore` |
| Theme and brand components | `Packages/PlinxUI` |
| Build, release, validation, and local development scripts | `scripts/` |

## Decision Checklist

Ask these in order:

1. Which concept does the change belong to, and where does that concept live
   today? Change it there.
2. Does the change affect what titles a family can see or play? Then it
   belongs in `Core/Safety` and `SafeMediaServicesTests`, not in a screen.
3. Is there already an implementation of this concept? Change or delete it
   instead of adding a second one.
4. Does the change rename a persisted key or file? Keep the old name, or add a
   migration that preserves families' sign-in and data.

## Working Policy

1. Do not override a type by excluding its file in `project.yml` and declaring
   a same-named replacement. Target exclusions are only for platform
   membership (iOS-only downloads and offline store, or a screen with its own
   tvOS version).
2. Delete code neither target reaches instead of stubbing it.
3. Upstream Strimr is a source of ideas and fixes, not a dependency. Port
   changes by hand following
   [upstream Strimr provenance](../maintenance/upstream-strimr.md), and judge
   each one against kid safety, zero collection, and the no-external-links
   rule.
4. Generic bug fixes can still be offered upstream as pull requests, but
   nothing in Plinx waits on upstream accepting them.
