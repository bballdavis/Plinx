# Strimr Contribution Plan: iOS Clear Title Logos

## Recommendation

Open a focused iOS feature issue, then port only the clear-logo behavior. Do not
resubmit the historical ratings work because current upstream already implements
ratings.

## Gap and Evidence

Current Strimr media details use text titles even when Plex supplies clear/title
logo art. Fork commits `87a9cd4` and `75fe05a` contain earlier implementations,
but the latter also mixes in now-redundant ratings and broader header styling.

## Proposed Change

1. Resolve Plex `Image` entries with the logo type in `MediaDetailViewModel` and
   expose a `titleLogoURL`.
2. Clear the published URL when the item changes, no logo exists, or resolution
   fails so stale art cannot cross details.
3. In the iOS media-detail header, show a centered, aspect-fit asynchronous
   image with the existing text title as loading/error fallback.
4. Preserve a useful accessibility label based on the media title.
5. Leave tvOS unchanged unless upstream explicitly requests platform parity in
   the issue.

## Scope Exclusions

- Ratings, banner art, button restyling, UIKit helpers, or hard-coded strings
- Plinx logo assets or branding rules
- Replacing the title when the server provides no usable logo

## Validation

- Unit-test logo selection, missing art, failed resolution, and item changes.
- Snapshot a logo, loading fallback, failed image, and long text title.
- Verify Dynamic Type, VoiceOver label, light/dark appearance, and compact iPhone
  layout.

## Upstream Shape

- Issue: `Show Plex clear/title logos in iOS media details`
- Branch: `feat/ios-clear-title-logos`
- Commit: `feat(ios): show Plex title logos`
- PR: `(iOS) feat: show Plex title logos`
- Dependency: use the current upstream ratings/header implementation as the
  baseline.
