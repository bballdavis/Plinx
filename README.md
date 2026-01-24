# Plinx

Plinx is a kid-first Plex media portal with a Liquid Glass UI, safety-first filtering, and parental controls.

## Repo Structure
- `Packages/PlinxCore` — safety, filtering, playback policy, haptics/audio managers.
- `Packages/PlinxUI` — Liquid Glass UI components and mascot views.
- `PlinxApp` — app shell and views (work in progress).
- `Vendor/Strimr` — upstream dependency (submodule).

## Local-Only Rules
All agent plans and instructions live under `.local_dev/` and are gitignored.
