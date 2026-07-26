# Strimr Contribution Plan: Search Visibility Parity

## Recommendation

Open an upstream issue because the change affects expected search semantics.
Keep it independent of Plinx safety policy and build it on Strimr's existing
library visibility settings.

## Gap and Evidence

Libraries hidden from normal Strimr navigation can reappear in search, and
search forces a movie/TV type restriction even when the user has not selected a
type filter. Fork commit `068f94a` demonstrates both gaps.

## Proposed Change

1. Inject the existing settings/library state into `SearchViewModel`.
2. Derive the set of visible section identifiers and reject a search result only
   when it has a section identifier that is not visible.
3. Retain results with no section identifier so discovery/global results do not
   disappear accidentally.
4. When no media-type filter is selected, omit the type restriction rather than
   forcing movie and TV types.
5. Preserve explicit movie/show filters exactly as they behave today.

## Scope Exclusions

- Plinx content ratings, parental policy, or kid-facing UI
- Server-side visibility mutation
- Adding new supported media models; clip support is a separate contribution

## Validation

- Search fixtures spanning visible, hidden, and missing section identifiers.
- Tests with no type filter and with each explicit type filter.
- Verify hidden libraries stay absent after refresh and library-setting changes.
- Confirm current movie/show search behavior remains unchanged.

## Upstream Shape

- Issue: `Keep search results consistent with hidden library settings`
- Branch: `fix/search-visible-libraries`
- Commit: `fix: respect library visibility in search`
- PR: `fix: respect hidden libraries in search`
- Dependency: clip support benefits from unrestricted search but can land
  independently.
