# Strimr Contribution Plan: SharePlay Presentation Capability

## Recommendation

Open an upstream design issue for a generic presentation capability. The
coordinator and engine integration should remain available while clients can
choose not to expose SharePlay initiation UI.

## Gap and Evidence

Current upstream renders SharePlay initiation controls directly in iOS and tvOS
media-detail surfaces. A downstream client cannot hide those controls without
copying upstream views or carrying a patch. Plinx must not expose social actions
in kid-facing UI, but the upstream seam should not mention Plinx or parental
policy.

## Proposed Change

1. Define a small environment/configuration value such as
   `SharePlayPresentationPolicy` with `.enabled` and `.hidden`, defaulting to
   `.enabled`.
2. Consult it wherever Strimr presents controls that start a SharePlay session.
3. Keep `SharePlayCoordinator` construction and playback integration intact so
   dependency injection and eligible joined sessions continue to work.
4. Make the value injectable at the app composition root and preview/test
   boundaries.
5. Document that the capability controls presentation, not platform entitlement
   or protocol support.

## Scope Exclusions

- Plinx safety types, parental gates, branding, or product names
- Removing SharePlay from Strimr
- Changing GroupActivities entitlement, session protocol, or AetherEngine
- Adding external links or explanatory web content to media details

## Validation

- Snapshot iOS and tvOS media details with the policy enabled and hidden.
- Assert no initiation action is discoverable through focus or accessibility
  when hidden.
- Verify enabled behavior and session startup are unchanged.
- Verify the app still compiles and the coordinator remains injectable in both
  modes.

## Upstream Shape

- Issue: `Allow clients to hide SharePlay initiation controls`
- Branch: `feat/shareplay-presentation-policy`
- Commit: `feat: add SharePlay presentation policy`
- PR: `feat: add a SharePlay presentation capability`
- Dependency: none; Plinx can carry the minimal seam until upstream accepts it.
