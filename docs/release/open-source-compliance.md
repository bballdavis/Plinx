# Open-Source Release Compliance

Plinx and the pinned Strimr source include GPL-licensed code. AetherEngine is
licensed under LGPL-3.0 with its documented App Store/DRM exception. This
document is an engineering checklist, not legal advice.

## Required Release Materials

For every distributed binary:

- preserve copyright and license notices;
- publish the exact Plinx commit used to build it;
- identify the exact Strimr commit from `config/release-dependencies.env` and
  the exact AetherEngine revision from `PlinxApp/project.yml`;
- include complete build instructions;
- make the complete corresponding source available for the shipped version;
- keep source/privacy/license links behind the parental gate in the app;
- obtain legal confirmation that the selected App Store EULA and distribution terms are compatible with the licenses before submission.

Run `scripts/build_compliance_bundle.sh` from a clean, committed release checkout. Keep the resulting archive with the App Store build records and publish it at the source URL referenced by the release.

`scripts/verify_release_dependency_state.sh` must pass first. It fails if the
live Strimr tree differs from the pinned revision, ensuring the sibling source
in the corresponding-source bundle matches the executable being archived.
AetherEngine and its transitive packages remain exact Swift Package Manager
source dependencies recorded by the generated package resolution.

## Strimr Compatibility Seams

The paired Strimr `dev-plinx` commit contains narrow, generic compatibility
seams that:

- propagates the persisted playback-level setting through the tvOS wrapper and reapplies it at MPV lifecycle boundaries;
- exposes an optional next-item authorization closure in both player wrappers so a host app can fail closed before autoplay or queue advancement.
- exposes default-allow item-authorization hooks in playlist and media-detail view models, allowing a host to filter their self-loading cached state without embedding Plinx policy in Strimr.

These seams require player-lifecycle and self-loading view-model injection
points that Plinx-owned adapters cannot provide from outside Strimr views.
Maintain them as independently reviewable upstream candidates and update the
pinned Strimr revision when they land.
