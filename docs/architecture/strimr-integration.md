# Strimr Integration

## Expected Local Layout

Sibling checkouts should look like:

```text
Repos/
  Plinx/
  strimr/
```

Plinx runtime builds currently expect the Strimr checkout at `../strimr` relative to the repo root and `../../strimr` relative to `PlinxApp/project.yml`.
AetherEngine is resolved by Swift Package Manager at the exact revision pinned
in `project.yml`; it is no longer a sibling checkout.

## Branch Pairing

Stable branch pairing:

- Plinx `main` ↔ Strimr `plinx-patches`
- Plinx `dev` ↔ Strimr `dev-plinx`

CI and release builds use an exact configured Strimr commit rather than
resolving a moving branch head. View the branch, commit, and upstream base on
the generated [current dependency status](../maintenance/current-dependencies.mdx)
page.

See `docs/development/branch-pairing.md` for commands and day-to-day verification steps.

## Integration Contract

`config/release-dependencies.env` is the single machine-readable contract for
the paired Strimr revision. Along with the exact commit, it records the paired
branch, upstream base, Plinx-compiled source roots, and narrow source seams.
`scripts/verify_strimr_integration_contract.sh --quick` verifies the static
source integration; `--full` additionally verifies the local Git pairing is
clean, pinned, based on the configured upstream commit, and linear. This keeps
the same-module integration explicit without treating Strimr's moving branch
head as a build dependency.

## When To Change Plinx Instead Of Strimr

Prefer Plinx-owned layers when the change is:

- product-specific
- kid-safety specific
- branding or copy specific
- a layout or UX override
- a narrow adaptation around upstream behavior

Preferred order:

1. Plinx view or view model
2. Plinx adapter or decorator
3. Plinx package API
4. minimal Strimr patch only if the above are not sufficient

## When Strimr Should Change

Patch the Strimr fork when the fix is generic and would still matter without the Plinx product, especially for:

- Plex networking or repositories
- playback engine behavior
- download engine behavior
- shared models and stores
- engine-level concurrency or lifecycle bugs

The migration keeps Plinx-only presentation, maximum-volume policy, and
fail-closed playback authorization out of generic upstream PRs. Reusable
filtering injection points, strict Plex boolean decoding, clip support, and the
SharePlay presentation policy are maintained as independently reviewable
upstream candidates.

## Upstream PR Candidate Criteria

Flag a Strimr-side change as an upstream candidate when it is:

- generic rather than Plinx-branded
- not dependent on Plinx-only product rules
- small enough to explain and review independently
- backed by a focused test or reproducible failure case

When a Plinx need forces a Strimr patch, document:

1. why the patch could not live in Plinx-owned layers
2. whether it is temporary or expected to remain upstreamable
3. which branch pairing or dependency assumption it relies on

## Current Release Patch

The pinned `dev-plinx` revision contains the Strimr-side injection points that
cannot be supplied by a Plinx decorator:

- host-app Plex product identity and encoded authentication-URL construction,
  required because Plex PIN creation headers and the browser claim URL must use
  the same product name before control returns to a Plinx-owned view;
- tvOS playback-gain propagation and MPV lifecycle reapplication;
- an optional authorization callback before autoplay or next-queue playback on iOS and tvOS;
- a default-enabled `showsBufferingOverlay` option on the iOS and tvOS player wrappers;
- default-allow playlist and media-detail cache authorization hooks required because those upstream views load their own models.

Plinx supplies the actual content decision in `StrimrAdapter`; Strimr remains unaware of Plinx policy or product copy.

## Download Queue Ownership

Download transcoding lives in Strimr because queue negotiation, polling,
background transfer, persisted recovery, and cleanup are generic Plex download
engine behavior. Original-quality downloads transfer the selected source part
directly. Reduced-quality downloads use Plex Media Server's versioned
`/downloadQueue` API and persist only the queue identifiers needed to resume a
request. Strimr does not know about Plinx profiles or kid policy.

Plinx owns the safety boundary around that engine. A newly enqueued local
download ID is claimed by the current server/profile identity, and lifecycle
resume passes only the IDs owned by that identity back to Strimr. Consequently,
switching Plex profiles cancels preparation polling for the prior profile and
cannot resume, clean up, or expose another profile's queued download. An
already-running background file transfer remains hidden and is subject to the
same ownership check before playback. Existing unowned downloads retain the documented
legacy visibility behavior, but only newly queued and explicitly owned items
can have server preparation resumed.

The server queue item is best-effort deleted after a validated local transfer
or explicit user deletion. Tokens, media paths, queue error text, account
identifiers, and server identifiers are not emitted to diagnostics or shown in
kid-facing UI. This Strimr change is an upstream PR candidate because the queue
transport and state machine are product-neutral; Plinx ownership filtering is
not part of that candidate.

The Plex identity seam reads the host bundle display name and falls back to
`Strimr`, so the generic client remains correctly branded while Plinx sends
`Plinx` consistently in both `X-Plex-Product` and the encoded browser
authorization context. This cannot live only in a Plinx adapter because the
paired Strimr networking clients construct those requests internally. The seam
is expected to remain upstreamable.

## Player Buffering Ownership

Strimr retains its native buffering overlay for existing consumers because
`showsBufferingOverlay` defaults to `true`. Plinx passes `false` at its player
boundary and renders `PlinxVideoBufferingOverlay` from
`PlayerViewModel.isLoading || PlayerViewModel.isBuffering`. That ensures the
compiled player presents exactly one loading indicator while keeping all Plinx
assets, copy, and animation rules in Plinx-owned code.

This is a narrow, generic upstream seam: hosts may replace presentation without
changing transport or buffering state. Strimr must not import `PlinxUI` or
encode Plinx branding. The literal option is part of
`STRIMR_REQUIRED_SEAMS`, so the quick integration contract fails if a paired
Strimr revision drops it.

## Home Catalog Loading

Plinx does not use Strimr's promoted Home hubs for recently-added library
rows. `LibraryCatalogLoader` requests each visible Plex section through
`/library/sections/{id}/all`, newest first, and applies the same
`MediaDisplayItem` mapping and content authorization used by Library Browse.
Results remain keyed by their source `Library`, so none-agent sections such as
YouTube cannot disappear because of hub classification or be merged into the
Movies row.

Continue Watching remains a promoted-hub concept. Its items pass through the
same app-internal content authorization adapter before appearing on Home.

## Player Control Presentation

Plinx excludes Strimr's `PlayerControlButtons.swift` from the iOS source set and
provides a same-module replacement in `Views/Player/`. This keeps the playback
engine and control actions upstream while Plinx owns its kid-focused control
size, contrast, and responsive layout. The replacement must continue to define
every button type consumed by Strimr's `PlayerControlsView`.
