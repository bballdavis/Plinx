# Retired Seam: Recently-Added Hub Classification

## Recommendation

Do not upstream or expand this classifier for Plinx. Home's recently-added rows
now load directly from each Plex library section, so promoted-hub identifiers
are no longer part of the Plinx integration contract.

## Gap and Evidence

Plex promoted hubs omitted a working YouTube library even though its section
endpoint returned eligible content. Identifier and localized-title heuristics
could not repair an absent hub and created a second content-loading structure
that diverged from Library Browse.

## Proposed Change

1. Load visible libraries through `/library/sections/{id}/all`.
2. Sort by `addedAt:desc`, exclude collections, and bound the initial result.
3. Map with `MediaDisplayItem.init(plexItem:)`.
4. Apply the global content policy without library-specific unrated exceptions.
5. Key results by `Library` and project them into the configured Home rows.

## Scope Exclusions

- Continue Watching, which remains a distinct promoted hub
- Changes to Strimr repositories or public APIs
- Library-specific rating or unrated exceptions

## Validation

- Contract coverage comparing Home and Library catalog results.
- Deterministic combined/split, visibility, ordering, deduplication, and partial-failure tests.
- Live parity coverage requiring a YouTube Home row when eligible section items exist.

## Upstream Shape

No Strimr contribution is required. The replacement is Plinx-owned and uses
existing Strimr section repositories and models.
