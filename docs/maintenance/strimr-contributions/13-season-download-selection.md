# Season Download Routing

## Problem

Strimr's season action enqueues the season's episodes directly. The iOS
media-detail download sheet remains show-scoped and allows episode selection;
Plinx does not replace that flow. Downloads are not incorporated into the tvOS
target.

## Current Downstream Patch

- Keep direct season enqueue behavior for season details.
- Keep the iOS episode-selection sheet available from show details.
- Reload an already-selected show season when its episode collection is empty.
- Keep downloads out of tvOS until that product surface is explicitly
  incorporated.

## Upstream Candidate

The obsolete season-scoped picker is not an upstream candidate. The shared
empty-season reload guard remains a small generic iOS media-detail fix because
the show picker can otherwise remain empty after an initial load failure.

## Upgrade Replay Checklist

1. Preserve direct season enqueue behavior unless the product explicitly
   requests season-level episode selection.
2. Preserve the show-level picker and completed-episode exclusion.
3. Keep the empty-season reload guard in the paired Strimr source.
4. Update required seams and the exact Strimr pin after pushing the sibling
   commit.

## Validation

- Build the Strimr iOS sources through Plinx for iPhone and iPad.
- Verify direct season enqueue remains available from season details.
- Verify the show picker can switch seasons and reload an empty selection.
- Verify Select All excludes completed episodes and submission de-duplicates.
- Verify the tvOS target does not compile download sources.
- Run the full Plinx-Strimr integration contract.
