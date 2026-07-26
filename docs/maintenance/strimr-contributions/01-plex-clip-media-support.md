# Strimr Contribution Plan: Plex Clip Media Support

## Recommendation

Open an upstream issue first, then rebuild the capability on current `main`.
Do not cherry-pick the old `pr/clip-type-support` branch: it contains unrelated
fork history.

## Gap and Evidence

Strimr's Plex models do not recognize `type=clip`, so Other Videos items are
dropped before browse, search, detail, playback, and download presentation can
agree on them. Plinx's working implementation originated in fork commit
`840c2ef`, but it needs to be decomposed and retested against the current shared
model layout.

## Proposed Change

1. Add `clip` to `PlexItemType` and the supported media-model conversions.
2. Treat a clip as playable video in `MediaItem`, `MediaDisplayItem`,
   `PlayableMediaItem`, image selection, cards, details, queues, and downloads.
3. Include clips when search is not explicitly restricted to movies or shows.
4. Add representative Plex fixtures for an Other Videos library and a clip with
   artwork, parts, and subtitles.
5. Continue rejecting unknown media types; clip support must not turn model
   decoding into an open-ended fallback.

## Scope Exclusions

- Plinx library-agent labels, artwork layout, branding, and kid-safety policy
- Download transcoding or quality-selection changes
- Any unrelated commits from the historical feature branch

## Validation

- Decode a real-shaped `type=clip` fixture.
- Browse, search, open details, enqueue, play, and download a clip on iOS and
  tvOS.
- Confirm movie, show, season, episode, and folder behavior is unchanged.
- Confirm unknown item types remain excluded.

## Upstream Shape

- Issue: `Support Plex clip items from Other Videos libraries`
- Branch: `feat/clip-media-support`
- Commit: `feat: support Plex clip media`
- PR: `feat: support Plex clip media`
- Dependency: coordinate with the search-visibility plan so unfiltered search
  can surface the newly supported type.
