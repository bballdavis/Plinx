# Season-Scoped Episode Download Selection

## Problem

Strimr's iOS media-detail download sheet must support both show-root and
selected-season details. A show picker may switch seasons, while a season
picker must remain constrained to the selected season. The tvOS target does
not incorporate downloads.

## Current Downstream Patch

- Open the episode-selection sheet for shows and seasons on iOS/iPadOS.
- Keep show scope switchable between seasons and constrain season scope to the
  selected season.
- Reload an already-selected season when its episode collection is empty.
- Distinguish loading, retryable errors, and genuine empty results.
- Keep completed episodes visible but unavailable for selection.
- Keep all download sources out of tvOS.

## Upstream Candidate

Contribute the scope enum, empty-season reload guard, error presentation, and
accessibility hooks as one generic iOS media-detail fix. The behavior contains
no Plinx branding or product policy; tvOS remains outside the download scope.

## Upgrade Replay Checklist

1. Check whether season details already offer episode selection upstream.
2. Drop the downstream patch if show and season scopes, retry states, and
   completed-episode exclusion are equivalent.
3. Otherwise replay only the generic iOS picker and empty-season reload guard.
4. Keep downloads excluded from tvOS and update required seams and the exact
   Strimr pin after pushing the sibling
   commit.

## Validation

- Build the Strimr iOS sources through Plinx for iPhone and iPad.
- Verify show scope can switch seasons.
- Verify season scope cannot escape the selected season.
- Verify failed season and episode requests offer retry instead of empty copy.
- Verify Select All excludes completed episodes and submission de-duplicates.
- Verify the picker accessibility identifiers through the iOS UI test.
- Verify the tvOS target does not compile download sources.
- Run the full Plinx-Strimr integration contract.
