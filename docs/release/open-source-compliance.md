# Open-Source Release Compliance

Plinx, the pinned Strimr source, and MPVKit-GPL include GPL-licensed code. This document is an engineering checklist, not legal advice.

## Required Release Materials

For every distributed binary:

- preserve copyright and license notices;
- publish the exact Plinx commit used to build it;
- identify the exact Strimr and MPVKit commits from `config/release-dependencies.env`;
- include the applied Strimr patch and complete build instructions;
- make the complete corresponding source available for the shipped version;
- keep source/privacy/license links behind the parental gate in the app;
- obtain legal confirmation that the selected App Store EULA and distribution terms are compatible with the licenses before submission.

Run `scripts/build_compliance_bundle.sh` from a clean, committed release checkout. Keep the resulting archive with the App Store build records and publish it at the source URL referenced by the release.

`scripts/verify_release_dependency_state.sh` must pass first. It fails if the live Strimr or MPVKit trees contain any source beyond the pinned revisions and documented patch, ensuring the corresponding-source bundle matches the executable being archived.

## Upstream Candidate

`patches/strimr-volume-cap.patch` is intentionally narrow and generic. It:

- propagates the persisted playback-level setting through the tvOS wrapper and reapplies it at MPV lifecycle boundaries;
- exposes an optional next-item authorization closure in both player wrappers so a host app can fail closed before autoplay or queue advancement.
- exposes default-allow item-authorization hooks in playlist and media-detail view models, allowing a host to filter their self-loading cached state without embedding Plinx policy in Strimr.

Both changes require player-lifecycle injection points that Plinx-owned adapters cannot provide from outside the Strimr views. Submit them upstream as separate reviewable changes; once released upstream, remove the local patch and update the pinned Strimr revision.
