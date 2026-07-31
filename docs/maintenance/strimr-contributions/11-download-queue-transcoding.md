# Strimr Contribution Plan: Plex Download Queue Transcoding

## Recommendation

Submit the repository, state-machine, and integrity changes as one focused
feature PR after confirming the request profile against a current Plex Media
Server. Keep Plinx's server/profile ownership filter in Plinx.

## Gap and Evidence

Strimr previously exposed several download-quality choices but ultimately
downloaded the original media part. Plex Media Server now provides a versioned
`/downloadQueue` API that can decide between direct play, direct stream, and
server transcode before exposing a downloadable media response.

## Proposed Change

1. Restore the persisted original, 1080p, 720p, 480p, and 360p quality presets.
2. Add a typed download-queue repository for queue creation, item submission,
   status polling, restart, media retrieval, and cleanup.
3. Persist queue identity and preparation state alongside the local download
   index so an interrupted app can continue monitoring server work.
4. Start the existing background `URLSession` transfer only after the queue
   item becomes available.
5. Preserve original-quality direct-play/direct-stream behavior while adding
   bitrate and resolution caps for reduced-quality presets.
6. Reject HTTP error bodies and structured HTML, JSON, or XML responses before
   moving staged content into playable storage.

## Scope Exclusions

- Plinx profile ownership and kid-facing presentation
- Advancing Plinx's paired Strimr pin
- Offline subtitle redesign
- Syncing local playback progress back to Plex

## Validation

- Unit-test every quality/profile mapping and original-quality omission.
- Decode persisted pre-feature download records.
- Exercise deciding, waiting, processing, available, expired, error, restart,
  relaunch, deletion, and cleanup paths.
- Run live direct-play and forced-transcode downloads against Plex Media Server
  1.41.9 or newer.
- Confirm no token, URL, media path, or server-provided error text is logged or
  surfaced.

## Upstream Shape

- Issue: `Support transcoded offline downloads through Plex Download Queue`
- Branch: `feat/download-queue-transcoding`
- Commit: `feat: add Plex download queue transcoding`
- PR: `feat: support quality-limited offline downloads`
- Dependency: preferably land download-integrity hardening first.
