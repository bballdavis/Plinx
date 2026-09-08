# Strimr Contribution Plan: Player Title Interaction Lifetime

## Problem

The iOS player schedules control dismissal three seconds after presentation.
A host-owned responsive title may need longer for a user to drag or press and
inspect overflow, but the shared player has no way to learn that the child is
being deliberately used.

## Generic Seam

Add a default-no-op `onTitleInteractionChanged` callback to the iOS
`PlayerControlsView` contract. `PlayerView` cancels its pending hide work while
interaction is active and restarts the ordinary inactivity timer on release.
Standalone Strimr keeps its current header and source compatibility; Plinx owns
the adaptive layout, overflow measurement, motion, and accessibility behavior.

## Validation

- Holding or dragging the overflowing title keeps controls visible.
- Releasing restores the existing three-second inactivity timeout.
- Ordinary playback controls and standalone Strimr behavior are unchanged.
- Reduce Motion disables automatic title travel while manual inspection and the
  full VoiceOver label remain available.

