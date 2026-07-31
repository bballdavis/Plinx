# Host-App Plex Authentication Identity

## Problem

Strimr constructs Plex cloud and server requests internally and hard-codes
`Strimr` as `X-Plex-Product`. A host application that supplies its own sign-in
surface can therefore create a PIN as one product and present the browser claim
URL as another. Plex authorization requires those identities to agree; the
mismatch also exposes Strimr branding in Plinx's authorized-device flow.

This cannot live only in a Plinx adapter because the paired Strimr networking
clients own the request headers and the iOS sign-in view model owns one of the
browser URLs.

## Current Downstream Patch

- Resolve the Plex product name from the host bundle's
  `CFBundleDisplayName`, then `CFBundleName`, with `Strimr` as the fallback.
- Use that value in both Plex cloud and server request headers.
- Build iOS, tvOS, macOS, and Plinx tvOS authorization URLs through one
  percent-encoding helper.
- Keep PIN codes and tokens out of logs and documentation.

Plinx tracks the required shared sources in `STRIMR_REQUIRED_SEAMS`.

## Upstream Candidate

Propose the identity resolver and URL builder as one small Strimr change. The
behavior is generic: standalone Strimr retains the `Strimr` name, while host
apps compiled from shared Strimr sources identify themselves consistently.

If upstream prefers explicit dependency injection, preserve the same contract:
one immutable product identity must be supplied to PIN creation, polling,
server requests, and browser URL construction.

## Upgrade Replay Checklist

1. Check whether upstream request builders still hard-code a product name.
2. Check every platform authentication URL for the same identity and encoded
   `context[device][product]` parameter.
3. Drop the downstream patch if upstream has an equivalent tested facility.
4. Otherwise replay the minimal generic seam without adding Plinx branding to
   Strimr.
5. Update the exact Strimr pin only after the sibling commit is pushed.

## Validation

- Unit-test display-name, bundle-name, blank-value, and `Strimr` fallback
  resolution.
- Parse the generated auth URL and verify client ID, code, and product survive
  percent encoding.
- Verify a Plinx-hosted PIN request and browser URL both identify `Plinx`.
- Build Plinx iOS and tvOS targets.
- Run `./scripts/verify_strimr_integration_contract.sh --full` against clean,
  pinned sibling checkouts.
