# Strimr Contribution Plan: Recently-Added Hub Classification

## Recommendation

Open a bug issue with sanitized Plex response examples before submitting code.
The contribution should be a pure identifier classifier.

## Gap and Evidence

Current Strimr identifies recently-added hubs only when the identifier contains
`recentlyadded`. Plex agents and library types can return dotted, underscored,
hyphenated, and media-specific recent identifiers. Fork commit `1b5fa57`
contains broader behavior, but also uses English title matching and public
logging that should not be upstreamed.

## Proposed Change

1. Normalize the machine identifier by lowercasing and removing known
   separators.
2. Recognize verified forms corresponding to `recentlyadded`,
   `home.recent`, `clips.recent`, and `videos.recent`.
3. Require a non-empty hub before classifying it as usable.
4. Keep classification independent of localized display titles.
5. Add table-driven tests using sanitized identifiers captured from Plex.

## Scope Exclusions

- English or localized title matching
- Logging hub titles, media names, account data, or full server responses
- Reordering unrelated home hubs

## Validation

- Positive tests for each documented identifier variant.
- Negative tests for unrelated “recent” hubs and empty hubs.
- Home tests for movie, show, and Other Videos libraries.

## Upstream Shape

- Issue: `Recognize Plex recently-added hub identifier variants`
- Branch: `fix/recently-added-hub-identifiers`
- Commit: `fix: classify Plex recently-added hub identifiers`
- PR: `fix: recognize recently-added hub variants`
- Dependency: clip support supplies the Other Videos fixture but is not required
  for the classifier itself.
