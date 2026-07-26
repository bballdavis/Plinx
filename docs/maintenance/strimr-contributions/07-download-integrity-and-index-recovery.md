# Strimr Contribution Plan: Download Integrity and Index Recovery

## Recommendation

Submit a focused reliability PR after duplicate-issue search. HTTP validation
and index recovery belong together because both prevent corrupt state from
being presented as a successful offline download.

## Gap and Evidence

Current Strimr can move an HTTP error body into the final media location because
it does not validate the response status before completing a download. It also
silently discards download-index persistence failures. Fork commits `32a7905`
and `ebdaf0b` contain earlier fixes.

## Proposed Change

1. Require an `HTTPURLResponse` with a successful `2xx` status before moving a
   staged media file.
2. Remove the staged response body and mark the task failed on invalid status.
3. Verify the staged file is non-empty and, when the server supplies a valid
   content length, reconcile it before completion.
4. Report index encode, write, read, and decode failures through the existing
   `ErrorReporter` using error/category data only.
5. On index read/decode failure, preserve the last valid in-memory state and
   leave the on-disk file available for diagnosis or later recovery.

## Scope Exclusions

- Arbitrary minimum file-size thresholds
- Tokens, URLs, paths, media titles, or account/server identifiers in diagnostics
- Download transcoding, quality profiles, network probing, or UI restyling

## Validation

- URL-protocol tests for `200`, redirects resolved to `2xx`, `401`, `404`, `500`,
  empty bodies, and length mismatch.
- Filesystem tests for unwritable, truncated, and invalid indexes.
- Confirm failed downloads never appear playable and successful downloads still
  survive relaunch.
- Review diagnostics for sensitive values.

## Upstream Shape

- Issue search: `Validate download responses and recover safely from index errors`
- Branch: `fix/download-state-integrity`
- Commit: `fix: validate downloaded files before completion`
- PR: `fix: harden download file and index integrity`
- Dependency: none.
