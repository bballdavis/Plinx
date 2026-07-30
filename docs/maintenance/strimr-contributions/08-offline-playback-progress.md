# Strimr Contribution Plan: Offline Playback Progress

## Recommendation

Open a feature issue first. Keep the initial implementation explicitly
device-local; server synchronization requires a separate product and conflict
resolution design.

## Gap and Evidence

Downloaded items do not preserve resume position or watched state when played
offline. Fork commits `5d31d4b` and `f41f6f6` add the core behavior, but it must
be adapted to the current AetherEngine lifecycle and shared download models.

## Proposed Change

1. Extend download metadata with optional `viewOffset`, `viewCount`, and
   `lastPlayedAt` fields using backward-compatible Codable defaults.
2. Construct local playable media from the persisted values.
3. Update progress from the player lifecycle, marking the beginning, resuming
   through the middle, and completing near the same threshold used online.
4. Persist updates atomically through the existing download index.
5. Make the UI refresh from the updated local record without requiring a server
   connection.

## Scope Exclusions

- Syncing offline progress back to Plex
- Multi-device conflict resolution
- Changes to online scrobble behavior
- Download-file integrity, which has its own PR plan

## Validation

- Decode existing metadata without the new fields.
- Start, pause, exit, resume, replay, and complete an offline item.
- Relaunch between progress updates and verify the values survive.
- Test iOS and tvOS lifecycle exits against AetherEngine.
- Confirm online playback progress is unchanged.

## Upstream Shape

- Issue: `Persist resume and watched state for offline playback`
- Branch: `feat/offline-playback-progress`
- Commit: `feat: persist offline playback progress`
- PR: `feat: persist offline playback progress`
- Dependency: preferably land download-integrity hardening first.
