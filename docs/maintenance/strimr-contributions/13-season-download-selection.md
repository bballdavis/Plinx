# Season-Scoped Episode Download Selection

## Problem

Strimr's iOS show download sheet assumes its detail model represents a show.
When a host opens a selected season, the existing season action bypasses the
picker and immediately enqueues every episode. A season-scoped picker cannot be
implemented in a Plinx adapter without replacing Strimr's media-detail header.

## Current Downstream Patch

- Resolve Plinx detail routes as the selected movie, show, season, or episode.
- Open the episode-selection sheet for shows and seasons.
- Keep show scope switchable between seasons and constrain season scope to the
  selected season.
- Reload an already-selected season when its episode collection is empty.
- Distinguish loading, retryable errors, and genuine empty results.
- Keep completed episodes visible but unavailable for selection.

## Upstream Candidate

Contribute the scope enum, idempotent episode reload, and error presentation as
one generic iOS media-detail fix. The behavior contains no Plinx branding or
product policy and preserves standalone Strimr's existing show picker.

## Upgrade Replay Checklist

1. Check whether season details already offer episode selection upstream.
2. Drop the downstream patch if show and season scopes, retry states, and
   completed-episode exclusion are equivalent.
3. Otherwise replay only the shared reload guard and iOS picker/header changes.
4. Update required seams and the exact Strimr pin after pushing the sibling
   commit.

## Validation

- Build the Strimr iOS sources through Plinx for iPhone and iPad.
- Verify show scope can switch seasons.
- Verify season scope cannot escape the selected season.
- Verify Select All excludes completed episodes and submission de-duplicates.
- Verify failed season and episode requests offer retry instead of empty copy.
- Run the full Plinx-Strimr integration contract.
