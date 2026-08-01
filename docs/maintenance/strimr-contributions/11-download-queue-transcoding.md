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
5. Download Original directly from the selected source part; use the background
   queue only for reduced-quality bitrate and resolution caps.
6. Reject HTTP error bodies and structured HTML, JSON, or XML responses before
   moving staged content into playable storage.
7. Decode the selected Plex part's source byte size and choose Original before
   transcoding when the requested video bitrate alone cannot produce a smaller
   file.
8. Compare a completed reduced-quality transfer with its source size. Discard
   it and transfer the original source directly when it provides no storage
   savings.
9. Force reduced-quality queue decisions by disabling direct play, direct
   stream, and automatic quality, and validate the typed `/decision` response
   before starting the device transfer.
10. Use a per-download session identifier and a documented replacement HTTP
    transcode target for MKV/H.264/AAC with stereo audio capped at 192 kbps.
11. Require at least 20 percent estimated and actual savings; persist a
    non-sensitive reason whenever Original is substituted or Plex rejects the
    requested profile.
12. Validate a resumed HTTP 206 transfer against the complete byte count from
    `Content-Range`, not the resumed segment's `Content-Length`, because the
    background session delivers the fully reassembled file.

## Scope Exclusions

- Plinx profile ownership and kid-facing presentation
- Advancing Plinx's paired Strimr pin
- Offline subtitle redesign
- Syncing local playback progress back to Plex

## Validation

- Unit-test every quality/profile mapping and original-quality omission.
- Decode persisted pre-feature download records.
- Decode metadata with and without the optional Plex part `size` field.
- Cover the bitrate estimate boundary and completed-file fallback without
  changing normal playback negotiation.
- Assert exact reduced-quality request flags, client-profile augmentation,
  per-item session identity, and decision-profile validation.
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
