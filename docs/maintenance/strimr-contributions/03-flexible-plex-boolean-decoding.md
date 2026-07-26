# Strimr Contribution Plan: Flexible Plex Boolean Decoding

## Recommendation

Submit a focused bug fix after checking for a duplicate issue. Keep the public
model property typed as `Bool?`; flexible wire decoding should be an internal
Plex compatibility detail.

## Gap and Evidence

Plex can encode boolean-like XML/JSON attributes as booleans, `0`/`1`, or
strings. Current Strimr still decodes fields such as `PlexItem.smart` directly
as `Bool?`, allowing one irregular value to fail the containing model. The
final behavior exists in fork commit `02d17bb`.

## Proposed Change

1. Add a private keyed-decoder helper that attempts `Bool`, integer `0`/`1`,
   and case-insensitive string forms `true`/`false` and `0`/`1`.
2. Use the helper only for Plex fields documented or observed to be
   boolean-like, beginning with `smart`.
3. Return `nil` for an absent value and throw a precise decoding error for
   unsupported non-null values.
4. Preserve the existing `Bool?` model API.

## Scope Exclusions

- Silent truthiness for arbitrary numbers or strings
- A public wrapper type that leaks transport irregularities into callers
- Unrelated tolerant decoding changes

## Validation

- Fixture tests for native booleans, integers, strings, missing, and null.
- Negative tests for `2`, empty string, and arbitrary text.
- A containing-library fixture proving one supported alternate encoding no
  longer rejects the response.

## Upstream Shape

- Issue search: `Plex boolean attributes fail decoding when encoded as 0/1`
- Branch: `fix/flexible-plex-booleans`
- Commit: `fix: decode Plex boolean variants`
- PR: `fix: decode Plex boolean variants`
- Dependency: none.
