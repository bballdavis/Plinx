# Strimr Contribution Plan: Library Filtering Seams

## Recommendation

Open an upstream design issue before implementation. Present this as a small,
generic view-model extension point for clients that must filter Plex content,
not as a Plinx safety feature.

## Gap and Evidence

Current Strimr library and home view models own mapping and pagination, leaving
downstream clients to copy whole view models if they must remove items or hubs.
Plinx's implementations in fork commits `06d89df`, `1759202`, and `02d17bb`
demonstrate the need, including the tvOS focus holes caused when pagination is
calculated before filtering.

## Proposed Change

1. Add optional item and hub transforms at the shared view-model boundary:
   `itemFilter: ((MediaDisplayItem) -> Bool)?` and
   `hubFilter: ((Hub) -> Hub?)?`.
2. Apply item filtering after Plex-to-display-model mapping and hub filtering
   before a hub is published.
3. On tvOS, maintain separate raw-source and displayed-item offsets so rejected
   rows do not consume a page or leave empty focus positions.
4. Let folders pass through unchanged and suppress character-index shortcuts
   when a filter makes the server's unfiltered index inaccurate.
5. Reset both offsets and derived index state on reload, library change, and
   filter change.

## Scope Exclusions

- Plinx `SafetyPolicy`, ratings, parental controls, or product naming
- A generalized query language
- Server-side Plex filters that cannot guarantee the same fail-closed result

## Validation

- Unit-test all-accepted, partly rejected, and all-rejected pages.
- Test enough rejected rows to require multiple raw fetches for one displayed
  page.
- Verify folders, refresh, sorting, library switching, and end-of-list state.
- Exercise tvOS focus traversal with no gaps and iOS/tvOS item parity.

## Upstream Shape

- Issue: `Add downstream filtering seams to shared library view models`
- Branch: `feat/library-filtering-seams`
- Commit: `feat: add library item and hub filtering seams`
- PR: `feat: add library filtering seams`
- Dependency: this should land before Plinx rebases its safety decorators.
